import Foundation
import Observation
import OSLog

/// S03 Conversation (UI_SCREENS S03, spec §6.2). Modes 1 listening, 2 transcript ready (1B.4a), 3 working and
/// 5 unsupported (1B.4b). Mode 4 follow-up comes with 1B.4c. The `/v1/parse` call that drives 3 / 5 is wired in 1B.10
/// through `showWorking()`, `showUnsupported(_:)` and `showParseFailed()`.
@Observable @MainActor final class ConversationViewModel {
    enum Mode: Equatable, Sendable {
        case listening
        case transcript
        case working
        case unsupported(Unsupported)
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

    private let repository: any TaskRepository
    private let speech: any SpeechService
    private let tts: any TTSService
    private let settings: AppSettings
    private let now: () -> Date
    private var listenTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private let silenceAfterSpeech: Duration
    private let noSpeechTimeout: Duration
    /// Text before "Nói lại"; restored when the new recording gives nothing, so a failed retry loses nothing (D-104).
    private var previousText = ""

    init(draftId: UUID?, repository: any TaskRepository, speech: any SpeechService, tts: any TTSService,
         localData: any LocalDataRepository, now: @escaping () -> Date = { .now },
         silenceAfterSpeech: Duration = ConversationViewModel.silenceAfterSpeech,
         noSpeechTimeout: Duration = ConversationViewModel.noSpeechTimeout) {
        self.draftId = draftId
        self.silenceAfterSpeech = silenceAfterSpeech
        self.noSpeechTimeout = noSpeechTimeout
        self.repository = repository
        self.speech = speech
        self.tts = tts
        self.now = now
        settings = localData.settings()
        if let draftId, let draft = repository.draft(draftId) {
            text = draft.originalInput
        }
    }

    /// Mic / widget entry (`.conversation(nil)`) starts listening; a saved draft opens as an editable transcript.
    // TODO(spec): a typed request from S02 "Gửi" should go straight to working (parse) — wired in 1B.10; until then it opens here.
    func onAppear() async {
        if draftId == nil, text.isEmpty { await listen() }
    }

    /// Leaving the screen stops mic and voice; the draft is already saved (D-104).
    func onDisappear() {
        tts.stop()
        silenceTask?.cancel()
        listenTask?.cancel()
        Task { await speech.stop() }
    }

    var canSend: Bool { mode == .transcript && !trimmed.isEmpty }

    /// Khoai avatar on assistant bubbles (P-41); hidden when `settings.pet` is off (D-289).
    var showsMascot: Bool { settings.petEnabled }

    // MARK: - Listening (mode 1)

    /// Starts a session and returns when it ended (final, stop, error). TTS stops first (spec §6.2 AC5).
    func listen() async {
        stopReading()
        listenTask?.cancel()
        noticeKey = nil
        previousText = text
        mode = .listening                                    // before clearing: no autosave of the empty text
        text = ""
        armAutoStop(after: noSpeechTimeout)
        let task = Task { @MainActor in
            do {
                for try await transcript in speech.start(locale: Self.locale) {
                    // On-device Speech can end with an empty "final" after `endAudio`; never let it wipe the
                    // words already shown (owner report 2026-11-10: "Gọi cho mẹ" vanished after "Dừng").
                    guard !transcript.text.isEmpty, transcript.text != text else { continue }
                    text = transcript.text
                    armAutoStop(after: silenceAfterSpeech)
                }
                finishListening(errorCode: nil)
            } catch {
                finishListening(errorCode: (error as? ServiceError)?.code ?? "speech.failed")
            }
        }
        listenTask = task
        await task.value
    }

    /// "Dừng" / the 140pt mic: ends recording; the stream then delivers the final text.
    func stopListening() async {
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
        mode = .transcript
        let heardNothing = trimmed.isEmpty
        if heardNothing, !previousText.isEmpty {
            text = previousText                               // mode is .transcript again → autosave sees the same text
        }
        if let errorCode {
            Self.logger.info("listening ended: \(errorCode, privacy: .public)")
            // TODO(spec): permission denied (`permission.microphone/speech.denied`) has no S03 text until S18 (1C.1);
            // every failure shows `conv.speech.unavailable` and the keyboard. `/v1/transcribe` fallback is 1B.12.
            noticeKey = heardNothing ? "conv.speech.unavailable" : nil
        } else if heardNothing {
            noticeKey = "conv.speech.empty"
        }
        autosave()
    }

    // MARK: - Working (mode 3) and unsupported (mode 5)

    /// Mode 3: spinner + "Mình đang soạn bản nháp…". The request text stays saved (D-104).
    func showWorking() {
        stopReading()
        noticeKey = nil
        mode = .working
    }

    /// "Hủy" while working: back to the editable text, nothing lost.
    // TODO(spec): 1B.10 also cancels the `/v1/parse` task here (ARCHITECTURE §8: leaving cancels the network task).
    func cancelWorking() {
        guard mode == .working else { return }
        mode = .transcript
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

    // MARK: - Transcript ready (mode 2)

    /// "Gửi": never automatic (API_CONTRACT §7.4). Saves the request; returns `true` when the screen may leave.
    // TODO(spec): 1B.10 replaces "save and go Home" with mode 3 (working) → `/v1/parse` → S04.
    func send() -> Bool {
        guard canSend else { return false }
        stopReading()
        autosave()
        return true
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
