import Foundation
import Observation

/// S23 "Khoai hướng dẫn" (4H.3, D-337, UI_SCREENS_P4 S23): one step at a time, large text, read aloud; hands-free
/// "tiếp" moves on (D-312). Curated guide on the phone first (D-338, no unit), else `POST /v1/guide` (1 unit) with
/// the question masked on the phone (D-340). Nothing runs on the phone: the user taps in the other app.
@Observable @MainActor final class GuideViewModel {
    enum Phase: Equatable {
        case loading
        case guide(Guide)
        /// `notAGuide` → "Chưa hỗ trợ" (DECISIONS §9.4).
        case unsupported
        case failed(UserMessage)
    }

    struct Voice: Sendable {
        var enabled = true
        var handsFree = true
        var rate = 0.45
    }

    let question: String
    private(set) var phase: Phase = .loading
    private(set) var index = 0
    private(set) var isReading = false
    /// Hands-free: listening for "tiếp" / "nói lại" / "quay lại" / "thôi".
    private(set) var isListening = false
    var quotaBlock: QuotaBlock?

    private let library: GuideLibrary
    private let api: any APIClientProtocol
    private let tts: any TTSService
    private let speech: (any SpeechService)?
    private let voice: Voice
    private let repository: (any TaskRepository)?
    /// 4H.5: the step is shared with the Hỏi Khoai panel and the Live Activity.
    private let sessions: GuideSessions?
    private let timeZoneId: String
    /// Spoken request + hands-free on: read each step and listen for "tiếp".
    private let spoken: Bool
    /// One key per question: "Thử lại" never charges twice (D-245).
    private let key = IdempotencyKey()
    private var handsFreeTask: Task<Void, Never>?

    init(question: String, spoken: Bool = false, library: GuideLibrary = .bundled, api: any APIClientProtocol,
         tts: any TTSService = MockTTSService(), speech: (any SpeechService)? = nil, voice: Voice = Voice(),
         repository: (any TaskRepository)? = nil, timeZoneId: String = TimeZone.current.identifier,
         sessions: GuideSessions? = nil) {
        self.repository = repository
        self.sessions = sessions
        self.timeZoneId = timeZoneId
        self.question = question
        self.spoken = spoken
        self.library = library
        self.api = api
        self.tts = tts
        self.speech = speech
        self.voice = voice
    }

    var guide: Guide? {
        if case .guide(let g) = phase { return g }
        return nil
    }

    var step: GuideResponse.Step? {
        guard let g = guide, g.steps.indices.contains(index) else { return nil }
        return g.steps[index]
    }

    var isLast: Bool { guide.map { index >= $0.steps.count - 1 } ?? true }

    /// "Bước 2/5".
    var stepLabel: String { Guide.stepLabel(index, of: guide?.steps.count ?? 0) }

    /// D-339: money = the AI / curated flag **or** the on-device keyword check.
    var isMoneyRelated: Bool { (guide?.isMoneyRelated ?? false) || GuideSafety.isMoneyRelated(question) }

    var isAIWritten: Bool {
        if case .ai = guide?.source { return true }
        return false
    }

    /// The 3 fixed warnings (app strings, D-339, D-220).
    static let fixedWarningKeys = ["guide.warning.otp", "guide.warning.authority", "guide.warning.rush"]

    // MARK: - Load

    func load() async {
        phase = .loading
        index = 0
        if let open = sessions?.current(for: question) {                  // 4H.5: from the panel, no second unit
            phase = .guide(open.guide)
            index = open.index
        } else {
            do {
                // D-338 curated first (no unit), else /v1/guide with the question masked (D-340)
                guard let guide = try await GuideLoader.load(question, library: library, api: api, key: key) else {
                    phase = .unsupported
                    return
                }
                phase = .guide(guide)
                sessions?.start(guide, question: question)
            } catch is CancellationError {
                return
            } catch {
                let code = (error as? AppError)?.code ?? "unknown"
                phase = .failed(UserMessage(key: ConversationViewModel.noticeKey(forParseError: code)))
                quotaBlock = QuotaBlock.from(error)                         // 402 → S16 / S17
                return
            }
        }
        startHandsFreeIfAllowed()
    }

    // MARK: - Steps

    func next() {
        guard let g = guide, index < g.steps.count - 1 else { return }
        index += 1
        sessions?.move(to: index)
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        sessions?.move(to: index)
    }

    /// Back from another app (4H.5): "tiếp" said to the panel moved the step; S23 shows the same one.
    func resume() {
        guard guide != nil, let open = sessions?.current(for: question), open.index != index else { return }
        stopHandsFree()
        index = open.index
    }

    /// "Xong" or leaving S23: the guide is closed (panel "tiếp" and the Live Activity end too).
    func leave() {
        stopHandsFree()
        sessions?.end()
    }

    /// What one step reads aloud: "Bước 2/5. <text>. <hint>".
    var spokenStep: String { guide?.spoken(index) ?? "" }

    /// The warnings read aloud before step 1 of a money guide (fixed first, then "Khoai nhận thấy").
    var spokenWarnings: String {
        guard isMoneyRelated else { return "" }
        let fixed = Self.fixedWarningKeys.map { UserMessage(key: $0).text }
        return (fixed + (guide?.scamWarnings ?? [])).joined(separator: " ")
    }

    /// "Nói lại" (tap again = stop).
    func readStep() async {
        if isReading { stopReading(); return }
        stopHandsFree()
        isReading = true
        await tts.speak(spokenStep, rate: voice.rate)
        isReading = false
    }

    func stopReading() {
        guard isReading else { return }
        tts.stop()
        isReading = false
    }

    // MARK: - Hands-free (D-312)

    private var isHandsFree: Bool { spoken && voice.enabled && voice.handsFree && speech != nil }

    /// Reads the warnings (money) and each step, then listens once: "tiếp" → next step, "nói lại" → the same,
    /// "quay lại" → back, "thôi" / silence → stops (the buttons still work). Ends after the last step.
    func startHandsFreeIfAllowed() {
        guard isHandsFree, guide != nil, handsFreeTask == nil else { return }
        handsFreeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.isMoneyRelated { await self.tts.speak(self.spokenWarnings, rate: self.voice.rate) }
            while !Task.isCancelled {
                await self.tts.speak(self.spokenStep, rate: self.voice.rate)
                guard !Task.isCancelled, !self.isLast, let speech = self.speech else { break }
                self.isListening = true
                let heard = await ListenOnce.listen(speech)
                self.isListening = false
                guard !Task.isCancelled else { break }
                switch GuideVoiceCommand.classify(heard) {
                case .next: self.next()
                case .previous: self.previous()
                case .repeatStep: continue
                case .stop, .other: return
                }
            }
        }
    }

    // MARK: - "Gọi cho con trước khi chuyển" (4H.4, D-339)

    /// A new request "Gọi cho con" → S03 (sent at once): `call.open` with the name resolved on the phone (nickname /
    /// Danh bạ, picker if several, D-106) → S04 → the user taps "Xác nhận" (D-100); iOS asks again before dialling.
    /// Returns the draft to open, nil without a repository (previews).
    func callFamilyDraft() -> UUID? {
        guard let repository else { return nil }
        stopHandsFree()
        let draft = TaskDraft(inputMode: .text, originalInput: UserMessage(key: "guide.callFamily.request").text,
                              timeZoneId: timeZoneId)
        repository.save(draft)
        return draft.id
    }

    /// Tests wait for the hands-free turn.
    func waitForHandsFree() async { await handsFreeTask?.value }

    /// Any tap, or leaving S23.
    func stopHandsFree() {
        handsFreeTask?.cancel()
        handsFreeTask = nil
        if isListening, let speech { Task { await speech.stop() } }
        isListening = false
        tts.stop()
    }

    /// "Bước tiếp" / "Bước trước" by tap: hands-free stops (the user took over).
    func tapNext() { stopHandsFree(); next() }
    func tapPrevious() { stopHandsFree(); previous() }
}
