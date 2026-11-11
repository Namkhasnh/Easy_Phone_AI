import Foundation
import Observation
import OSLog

/// S03 Conversation (UI_SCREENS S03, spec §6.2). Modes 1 listening, 2 transcript ready (1B.4a), 3 working,
/// 5 unsupported (1B.4b), 4 follow-up (1B.4c). 1B.14b: "Gửi" → `/v1/parse` → `TaskEngine.applyParsed` → the ONE
/// question (`TaskEngine.nextFollowUp`, D-281) or S04 (`reviewDraftId`); a chip is applied on device (D-251), a typed /
/// spoken answer is a new `/v1/parse` with `context` → `TaskEngine.mergeAnswer` (ARCHITECTURE §6.2).
@Observable @MainActor final class ConversationViewModel {
    enum Mode: Equatable, Sendable {
        case listening
        case transcript
        case working
        case unsupported(Unsupported)
        case followUp(FollowUp)
    }

    /// Mode 4: the ONE question (spec §6.2 AC3). `question` is already chosen by the D-281 rule (1B.14):
    /// `followUpQuestion` or the `followup.<kind>.<fieldId>` text.
    struct FollowUp: Equatable, Sendable {
        let question: String
        var chips: [DateChip] = []
    }

    /// A `dateCandidates` entry (DATA_MODEL §6.2): `{ fieldId, value, label }`. Tapping it resolves the field on device.
    struct DateChip: Equatable, Hashable, Sendable, Identifiable {
        let fieldId: String
        let value: String
        let label: String
        var id: String { fieldId + "|" + value }
    }

    /// What the user gave in mode 4; consumed by the follow-up loop (1B.14).
    enum FollowUpAnswer: Equatable, Sendable {
        case chip(DateChip)          // D-251: on device, no `/v1/parse`, no unit
        case text(String)            // typed / spoken: a new `/v1/parse` with context (ARCHITECTURE §6.2)
        case skipped                 // "Bỏ qua, tôi sẽ sửa sau" → S04
    }

    /// `ParsedDraft.unsupported` (API_CONTRACT §7.1): `reason` ∈ recurringEvent, bulkAction, phaseNotEnabled, booking,
    /// other; `message` is the backend's Vietnamese sentence, shown as data under "Chưa hỗ trợ" (DATA_MODEL §6.2).
    struct Unsupported: Equatable, Sendable {
        let reason: String
        let message: String?
    }

    /// The secondary button of mode 5 (UI_SCREENS S03).
    enum UnsupportedAction: Equatable, Sendable {
        case rephrase                    // "Thử cách nói khác"
        case openList(Route)             // bulkAction (D-280): "Mở danh sách để làm từng việc"
    }

    static let locale = Locale(identifier: "vi-VN")
    static let hintKeys = ["conv.listening.hint.1", "conv.listening.hint.2", "conv.listening.hint.3"]
    /// UI_SCREENS S03 (DOC-29): silence after the last recognized words → stop by itself, like Siri. "Dừng" stays visible (AC1).
    static let silenceAfterSpeech: Duration = .seconds(2)
    /// Nothing recognized at all → stop and show `conv.speech.empty`.
    static let noSpeechTimeout: Duration = .seconds(8)

    private(set) var mode: Mode = .transcript
    /// Live transcript while listening; the editable request afterwards. Edits autosave (D-104).
    var text = "" {
        didSet { if mode == .transcript, text != oldValue { autosave() } }
    }
    /// `conv.speech.unavailable` / `conv.speech.empty` / `conv.parseFailed` under the text area, or `nil`.
    private(set) var noticeKey: String?
    private(set) var isReading = false
    private(set) var draftId: UUID?
    /// Mode 4 answer field (typed or spoken).
    var answerText = ""
    /// Last answer given in mode 4.
    private(set) var lastAnswer: FollowUpAnswer?
    /// The question shown in mode 4 (which step / field the answer is for).
    private(set) var prompt: FollowUpPrompt?
    /// Set when nothing is left to ask: the View replaces S03 with S04 of this draft.
    private(set) var reviewDraftId: UUID?
    /// S18 before the mic starts: microphone, then speech (D-185). The recording waits for the answer.
    var pendingPermission: PendingPermission?
    private var pendingTarget: Target?
    private let permissions: any PermissionManager

    private let repository: any TaskRepository
    private let speech: any SpeechService
    private let api: any APIClientProtocol
    /// `/v1/transcribe` fallback in flight (1B.12), and where "Hủy" / the result returns to.
    private var transcribeTask: Task<Void, Never>?
    private var workingReturnMode: Mode?
    private let tts: any TTSService
    private let settings: AppSettings
    private let localData: any LocalDataRepository
    private let engine: TaskEngine
    /// `/v1/parse` in flight; "Hủy" / leaving cancels it (ARCHITECTURE §8).
    private var parseTask: Task<Void, Never>?
    /// How the current mode-4 answer was given (`ParseRequest.inputMode`).
    private var answerInputMode: InputMode = .text
    private let now: () -> Date
    private var listenTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private let silenceAfterSpeech: Duration
    private let noSpeechTimeout: Duration
    /// Text before "Nói lại"; restored when the new recording gives nothing, so a failed retry loses nothing (D-104).
    private var previousText = ""
    /// Where a recording goes: the request (modes 1–2) or the follow-up answer (mode 4).
    private enum Target { case request, answer(FollowUp) }
    private var target: Target = .request
    /// D-296: "Dừng" was tapped → show the transcript, never auto-send.
    private var stoppedByUser = false
    /// D-296: set by `finishListening` when listening ended by itself with words heard and `settings.autoSend` is on.
    private var autoSendPending = false

    init(draftId: UUID?, repository: any TaskRepository, speech: any SpeechService, api: any APIClientProtocol,
         tts: any TTSService, localData: any LocalDataRepository,
         permissions: any PermissionManager = MockPermissionManager(), engine: TaskEngine? = nil,
         now: @escaping () -> Date = { .now },
         silenceAfterSpeech: Duration = ConversationViewModel.silenceAfterSpeech,
         noSpeechTimeout: Duration = ConversationViewModel.noSpeechTimeout) {
        self.draftId = draftId
        self.silenceAfterSpeech = silenceAfterSpeech
        self.noSpeechTimeout = noSpeechTimeout
        self.repository = repository
        self.speech = speech
        self.api = api
        self.tts = tts
        self.now = now
        self.localData = localData
        self.permissions = permissions
        self.engine = engine ?? TaskEngine(repository: repository)   // tests pass one with their clock
        settings = localData.settings()
        if let draftId, let draft = repository.draft(draftId) {
            text = draft.originalInput
        }
    }

    /// Mic / widget entry (`.conversation(nil)`) starts listening. A draft with steps resumes at its next question (or
    /// S04). A typed request from S02 "Gửi" (text draft, never parsed) goes straight to mode 3 — the user already
    /// tapped "Gửi" there. Any other saved draft opens as an editable transcript.
    // TODO(spec): `Route.conversation(UUID?)` carries no "send now" flag; "S02 typed" = `.text` draft without steps and
    // without `serverRequestId`.
    func onAppear() async {
        if draftId == nil, text.isEmpty { await listen(); return }
        guard let draft = currentDraft else { return }
        if !draft.steps.isEmpty {
            advance(draft)
        } else if draft.inputMode == .text, draft.serverRequestId == nil, mode == .transcript, !trimmed.isEmpty {
            await send()
        }
    }

    private var currentDraft: TaskDraft? { draftId.flatMap { repository.draft($0) } }

    /// Leaving the screen stops mic and voice; the draft is already saved (D-104).
    func onDisappear() {
        tts.stop()
        silenceTask?.cancel()
        listenTask?.cancel()
        transcribeTask?.cancel()
        parseTask?.cancel()
        Task { await speech.stop() }
    }

    var canSend: Bool { mode == .transcript && !trimmed.isEmpty }

    /// Khoai avatar on assistant bubbles (P-41); hidden when `settings.pet` is off (D-289).
    var showsMascot: Bool { settings.petEnabled }

    /// UI_SCREENS S03: listening → `listening`, working → `thinking`, follow-up → `asking`, unsupported / any notice
    /// (parse failed, speech empty, errors) → `sorry`.
    var mascotPose: MascotPose {
        switch mode {
        case .unsupported: return .sorry
        case _ where noticeKey != nil: return .sorry
        case .working: return .thinking
        case .followUp: return .asking
        case .listening, .transcript: return .listening
        }
    }

    // MARK: - Listening (mode 1)

    /// Starts a session for the request and returns when it ended (final, stop, error). TTS stops first (AC5).
    func listen() async { await record(.request) }

    /// Mode 4 mic: records the answer, then returns to the same question.
    func listenForAnswer() async {
        guard case .followUp(let f) = mode else { return }
        await record(.answer(f))
    }

    /// Text shown live while listening.
    var listeningText: String {
        if case .answer = target { return answerText }
        return text
    }

    /// Step 0 for the mic (D-185): the first capability never asked → S18 explainer; denied → S18 denied + keyboard.
    /// Returns true when recording may start.
    private func permissionsReady(for target: Target) -> Bool {
        for capability in [Capability.microphone, .speech] {
            switch permissions.status(capability) {
            case .notDetermined:
                pendingTarget = target
                pendingPermission = PendingPermission(capability: capability, variant: .explainer)
                return false
            case .denied, .restricted:
                pendingTarget = nil
                pendingPermission = PendingPermission(capability: capability, variant: .denied)
                return false
            case .granted, .limited, .writeOnly:
                continue
            }
        }
        return true
    }

    /// S18 "Cho phép": the system alert; usable → the next capability or the recording, else the denied variant.
    func allowPermission() async {
        guard let pending = pendingPermission, pending.variant == .explainer, let target = pendingTarget else { return }
        pendingPermission = nil
        let status = await permissions.request(pending.capability)
        guard status.isUsable else {
            pendingTarget = nil
            pendingPermission = PendingPermission(capability: pending.capability, variant: .denied)
            return
        }
        await record(target)
    }

    /// S18 "Để sau" / "Mở Cài đặt" / swipe down: no recording; the text field stays (fallback "Gõ chữ").
    func dismissPermission() {
        pendingPermission = nil
        pendingTarget = nil
    }

    private func record(_ target: Target) async {
        guard permissionsReady(for: target) else { return }
        stopReading()
        listenTask?.cancel()
        noticeKey = nil
        self.target = target
        mode = .listening                                    // before clearing: no autosave of the empty text
        if case .answer = target {
            previousText = answerText
            answerText = ""
        } else {
            previousText = text
            text = ""
        }
        stoppedByUser = false
        autoSendPending = false
        armAutoStop(after: noSpeechTimeout)
        let task = Task { @MainActor in
            do {
                for try await transcript in speech.start(locale: Self.locale) {
                    // On-device Speech can end with an empty "final" after `endAudio`; never let it wipe the
                    // words already shown (owner report 2026-11-10: "Gọi cho mẹ" vanished after "Dừng").
                    guard !transcript.text.isEmpty, transcript.text != listeningText else { continue }
                    if case .answer = self.target { answerText = transcript.text } else { text = transcript.text }
                    armAutoStop(after: silenceAfterSpeech)
                }
                finishListening(errorCode: nil)
            } catch {
                finishListening(errorCode: (error as? ServiceError)?.code ?? "speech.failed")
            }
        }
        listenTask = task
        await task.value
        await transcribeTask?.value                           // a `/v1/transcribe` fallback started by this session
        // D-296: auto-send when listening stopped by itself (2 s silence). Nothing runs before "Xác nhận" (D-100).
        guard autoSendPending else { return }
        autoSendPending = false
        switch mode {
        case .transcript: await send()
        case .followUp: await sendAnswer()
        default: break
        }
    }

    /// "Dừng" / the 140pt mic: ends recording; the stream then delivers the final text.
    func stopListening() async {
        stoppedByUser = true
        await speech.stop()
    }

    /// Restarts the silence timer; when it fires while still listening, recording stops like "Dừng".
    private func armAutoStop(after delay: Duration) {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.mode == .listening else { return }
            await self.speech.stop()
        }
    }

    /// "Nói lại": replaces the text with a new recording (same draft).
    func speakAgain() async { await listen() }

    private func finishListening(errorCode: String?) {
        guard mode == .listening else { return }
        silenceTask?.cancel()
        let heardNothing: Bool
        switch target {
        case .request:
            mode = .transcript
            heardNothing = trimmed.isEmpty
            if heardNothing, !previousText.isEmpty {
                text = previousText                           // mode is .transcript again → autosave sees the same text
            }
        case .answer(let followUp):
            mode = .followUp(followUp)
            heardNothing = answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if heardNothing { answerText = previousText } else { answerInputMode = .voice }
        }
        let finishedTarget = target
        target = .request
        if let errorCode {
            Self.logger.info("listening ended: \(errorCode, privacy: .public)")
            if errorCode == Self.viUnavailable, heardNothing {
                // ARCHITECTURE §4.3: no on-device Vietnamese → upload the recording to `/v1/transcribe` (1B.12).
                // TODO(spec): "or confidence is low" (§4.3) has no threshold in the docs; only "unavailable" falls back.
                autosave()
                startTranscribeFallback(for: finishedTarget)
                return
            }
            // Permission denied is explained by S18 before recording (D-185); a late denial and every other failure
            // show `conv.speech.unavailable` and the keyboard.
            noticeKey = heardNothing ? "conv.speech.unavailable" : nil
        } else if heardNothing {
            noticeKey = "conv.speech.empty"
        } else if !stoppedByUser, settings.autoSend {
            autoSendPending = true
        }
        autosave()
    }

    static let viUnavailable = "speech.vi.unavailable"

    /// Mode 3 while the recording is transcribed by the backend. The result is only shown, never sent (AC1, §7.4).
    // TODO(spec): S03 has no "đang chuyển giọng nói" text; mode 3 shows `conv.working` meanwhile.
    private func startTranscribeFallback(for target: Target) {
        let returnMode = mode                               // .transcript or .followUp(…)
        workingReturnMode = returnMode
        mode = .working
        transcribeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let audio = await self.speech.recordedAudio(), !audio.isEmpty else {
                self.endTranscribe(nil, unavailable: true, target: target)
                return
            }
            do {
                let result = try await self.api.transcribe(m4a: audio, meta: .vietnamese)
                guard !Task.isCancelled else { return }
                self.endTranscribe(result.text, unavailable: false, target: target)
            } catch {
                guard !Task.isCancelled else { return }
                // D-059: code only. 429 / spend cap / offline → keyboard (ARCHITECTURE §9.2).
                Self.logger.info("transcribe failed: \((error as? AppError)?.code ?? "unknown", privacy: .public)")
                self.endTranscribe(nil, unavailable: true, target: target)
            }
        }
    }

    private func endTranscribe(_ result: String?, unavailable: Bool, target: Target) {
        guard mode == .working, let returnMode = workingReturnMode else { return }   // "Hủy" already left
        workingReturnMode = nil
        mode = returnMode
        let words = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if words.isEmpty {
            noticeKey = unavailable ? "conv.speech.unavailable" : "conv.speech.empty"
            return
        }
        switch target {
        case .request: text = words                         // mode is .transcript → autosave (D-104)
        case .answer: answerText = words; answerInputMode = .voice
        }
    }

    // MARK: - Working (mode 3) and unsupported (mode 5)

    /// Mode 3: spinner + "Oki, bạn đợi mình chút…". The request text stays saved (D-104).
    func showWorking() {
        stopReading()
        noticeKey = nil
        mode = .working
    }

    /// "Hủy" while working: back to the editable text (or the question), nothing lost. Cancels the network task.
    func cancelWorking() {
        guard mode == .working else { return }
        transcribeTask?.cancel()
        parseTask?.cancel()
        mode = workingReturnMode ?? .transcript
        workingReturnMode = nil
    }

    /// Mode 5 (spec §11, D-280). Builds no steps.
    func showUnsupported(_ unsupported: Unsupported) {
        stopReading()
        noticeKey = nil
        mode = .unsupported(unsupported)
    }

    /// Parse failed (`llm_invalid_output` after the repair, spec §6.2 AC2): back to the text with `conv.parseFailed`.
    func showParseFailed() {
        mode = .transcript
        noticeKey = "conv.parseFailed"
    }

    /// The backend sentence, or `nil` when it is empty.
    var unsupportedMessage: String? {
        guard case .unsupported(let u) = mode, let m = u.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !m.isEmpty else { return nil }
        return m
    }

    /// Mode 5 secondary. `bulkAction` always opens S11 (DOC-30, AI_PROMPTS §8 table).
    // TODO(spec): `recurringEvent` "Tạo nhắc một lần cho sáng mai?" stays hidden until DraftBuilder (1B.13) can build it (owner 2026-11-10).
    var unsupportedAction: UnsupportedAction {
        if case .unsupported(let u) = mode, u.reason == "bulkAction" { return .openList(.calendarToday) }
        return .rephrase
    }

    /// "Thử cách nói khác": back to the saved text to edit it or speak again.
    func rephrase() {
        noticeKey = nil
        mode = .transcript
    }

    // MARK: - Follow-up (mode 4)

    /// Shows the ONE question (spec §6.2 AC3); the answer field starts empty.
    func showFollowUp(_ followUp: FollowUp) {
        stopReading()
        noticeKey = nil
        answerText = ""
        answerInputMode = .text
        mode = .followUp(followUp)
    }

    var canSendAnswer: Bool {
        guard case .followUp = mode else { return false }
        return !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Chip tap: resolved on device through `TaskEngine.edit` (`source = .user`, ambiguity cleared), never an AI call
    /// or a unit (D-251). Then the next question or S04.
    func pick(_ chip: DateChip) {
        guard case .followUp(let f) = mode, f.chips.contains(chip) else { return }
        lastAnswer = .chip(chip)
        guard let prompt, prompt.fieldId == chip.fieldId, let draft = currentDraft else { return }
        stopReading()
        engine.edit(fieldId: chip.fieldId, value: chip.value, stepId: prompt.stepId, in: draft)
        advance(draft)
    }

    /// "Gửi" under the answer field: never automatic (API_CONTRACT §7.4). A new `/v1/parse` (new key, 1 unit) with
    /// `context` = this draft without 🔒 fields (D-056), then merged (`.user` fields kept).
    func sendAnswer() async {
        guard canSendAnswer, case .followUp(let followUp) = mode else { return }
        stopReading()
        let answer = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastAnswer = .text(answer)
        guard let prompt, let draft = currentDraft else { return }
        let context = ParseRequest.ParseContext(draftId: draft.id, answeringFieldId: prompt.fieldId,
                                                currentDraft: DraftBuilder.wireDraft(draft))
        await runParse(text: answer, inputMode: answerInputMode, context: context, draft: draft,
                       returnMode: .followUp(followUp))
    }

    /// "Bỏ qua, tôi sẽ sửa sau": the draft opens in S04 with the field still empty. Returns the draft to open.
    func skipFollowUp() -> UUID? {
        guard case .followUp = mode else { return nil }
        lastAnswer = .skipped
        return draftId
    }

    // MARK: - Transcript ready (mode 2)

    /// "Gửi", or automatic after listening stops by itself when `settings.autoSend` is on (D-296). Saves the request (D-104), then mode 3 → `/v1/parse` (new key).
    func send() async {
        guard canSend else { return }
        stopReading()
        autosave()
        guard let draft = currentDraft else { return }
        guard draft.steps.isEmpty else { advance(draft); return }       // already parsed: never charge twice
        await runParse(text: trimmed, inputMode: draft.inputMode, context: .none, draft: draft, returnMode: .transcript)
    }

    // MARK: - Parse loop (ARCHITECTURE §6.2)

    private func runParse(text: String, inputMode: InputMode, context: ParseRequest.ParseContext, draft: TaskDraft,
                          returnMode: Mode) async {
        noticeKey = nil
        workingReturnMode = returnMode
        mode = .working
        let zone = TimeZone(identifier: draft.timeZoneId) ?? .current
        let request = ParseRequest(text: text, inputMode: inputMode, now: ParseRequest.nowString(now(), in: zone),
                                   timezone: zone.identifier, locale: draft.locale,
                                   savedPlaceLabels: savedPlaceLabels, context: context)
        let key = IdempotencyKey()                                     // one per call; retries inside APIClient reuse it
        let isAnswer = context.answeringFieldId != nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let parsed = try await self.api.parse(request, idempotencyKey: key)
                guard !Task.isCancelled, self.mode == .working else { return }   // "Hủy" already left
                self.workingReturnMode = nil
                await self.handle(parsed, isAnswer: isAnswer, draft: draft, returnMode: returnMode)
            } catch {
                guard !Task.isCancelled, self.mode == .working else { return }
                self.workingReturnMode = nil
                self.fail(error, returnMode: returnMode)
            }
        }
        parseTask = task
        await task.value
    }

    /// DATA_MODEL §5: labels only (`home`, `work`, `custom`), never addresses.
    private var savedPlaceLabels: [String] {
        var seen = Set<String>()
        return localData.savedPlaces().map(\.label).filter { seen.insert($0).inserted }
    }

    private func handle(_ parsed: ParsedDraft, isAnswer: Bool, draft: TaskDraft, returnMode: Mode) async {
        let defaults = DraftBuilder.Defaults(mapsApp: settings.preferredMapsApp)
        if isAnswer {
            guard parsed.unsupported == nil else {
                // TODO(spec): an `unsupported` reply to a follow-up answer is not specified; the same question is
                // asked again with `conv.parseFailed` (the draft keeps its steps).
                mode = returnMode
                noticeKey = "conv.parseFailed"
                return
            }
            engine.mergeAnswer(parsed, into: draft, defaults: defaults)
            await resolveThenAdvance(draft)
            return
        }
        if let u = parsed.unsupported {
            showUnsupported(.init(reason: u.reason, message: u.message))
        } else if engine.applyParsed(parsed, to: draft, defaults: defaults) {
            await resolveThenAdvance(draft)
        } else {
            // Every step dropped on device (unknown kind / pair, D-150): nothing to review → "Chưa hỗ trợ" (spec §11).
            showUnsupported(.init(reason: "other", message: nil))
        }
    }

    /// Contacts / calendar lookups on device (1C.9), then the next question or S04. Mode 3 stays on meanwhile.
    private func resolveThenAdvance(_ draft: TaskDraft) async {
        await engine.resolveDevice(in: draft)
        advance(draft)
    }

    /// The next ONE question (D-281) or S04 when nothing S03 can ask is left.
    private func advance(_ draft: TaskDraft) {
        if let next = engine.nextFollowUp(in: draft) {
            prompt = next
            showFollowUp(FollowUp(question: next.question, chips: next.candidates.map {
                DateChip(fieldId: next.fieldId, value: $0.id, label: $0.title)
            }))
        } else {
            prompt = nil
            reviewDraftId = draft.id
        }
    }

    /// ARCHITECTURE §9.2 for parse: back to where the user was, text kept, one notice. "Gửi" again = "Thử lại" (new key).
    private func fail(_ error: any Error, returnMode: Mode) {
        let code = (error as? AppError)?.code ?? "generic"
        Self.logger.info("parse failed: \(code, privacy: .public)")       // D-059: code only
        mode = returnMode
        noticeKey = Self.noticeKey(forParseError: code)
    }

    /// `error.<code>` keys of UI_SCREENS §8 used by S03; unknown → `error.generic`.
    // TODO(spec): 402 should open S16 / S17 (1F); until then the notice `error.quota_exceeded` is shown.
    static func noticeKey(forParseError code: String) -> String {
        if code.hasPrefix("network.") { return "error.network.offline" }
        switch code {
        case APIErrorCode.llmInvalidOutput: return "conv.parseFailed"
        case APIErrorCode.quotaExceeded, APIErrorCode.spendCap, APIErrorCode.internal, APIErrorCode.upstreamError,
             "invalid_input", "not_found", "payload_too_large":
            return "error.\(code)"
        default: return "error.generic"
        }
    }

    /// "Đọc to" on the user bubble (S03) at the Settings rate; tap again = "Dừng đọc".
    func toggleReading() async {
        if isReading { stopReading(); return }
        guard !trimmed.isEmpty else { return }
        isReading = true
        await tts.speak(trimmed, rate: settings.speechRate)
        isReading = false
    }

    func stopReading() {
        guard isReading else { return }
        tts.stop()
        isReading = false
    }

    // MARK: - Autosave (D-104)

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The first non-empty text creates the draft; later edits update `originalInput`. Nothing is created for empty text.
    private func autosave() {
        if let draftId, let draft = repository.draft(draftId) {
            guard draft.originalInput != text else { return }
            draft.originalInput = text
            draft.updatedAt = now()
            repository.save(draft)
        } else if !trimmed.isEmpty {
            let draft = TaskDraft(createdAt: now(), inputMode: .voice, originalInput: text)
            repository.save(draft)
            draftId = draft.id
        }
    }

    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "conversation")
}
