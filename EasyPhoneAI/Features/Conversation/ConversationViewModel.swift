import Foundation
import Observation
import OSLog

/// S03 Conversation (UI_SCREENS S03, spec §6.2 AC1 / AC5). Sub-step 1B.4a: modes 1 (listening) and 2 (transcript ready).
/// Modes 3–5 (working, follow-up, unsupported) come with 1B.4b / 1B.4c.
@Observable @MainActor final class ConversationViewModel {
    enum Mode: Equatable, Sendable {
        case listening
        case transcript
    }

    static let locale = Locale(identifier: "vi-VN")
    static let hintKeys = ["conv.listening.hint.1", "conv.listening.hint.2", "conv.listening.hint.3"]

    private(set) var mode: Mode = .transcript
    /// Live transcript while listening; the editable request afterwards. Edits autosave (D-104).
    var text = "" {
        didSet { if mode == .transcript, text != oldValue { autosave() } }
    }
    /// `conv.speech.unavailable` / `conv.speech.empty` under the text area, or `nil`.
    private(set) var noticeKey: String?
    private(set) var isReading = false
    private(set) var draftId: UUID?

    private let repository: any TaskRepository
    private let speech: any SpeechService
    private let tts: any TTSService
    private let settings: AppSettings
    private let now: () -> Date
    private var listenTask: Task<Void, Never>?
    /// Text before "Nói lại"; restored when the new recording gives nothing, so a failed retry loses nothing (D-104).
    private var previousText = ""

    init(draftId: UUID?, repository: any TaskRepository, speech: any SpeechService, tts: any TTSService,
         localData: any LocalDataRepository, now: @escaping () -> Date = { .now }) {
        self.draftId = draftId
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
        let task = Task { @MainActor in
            do {
                for try await transcript in speech.start(locale: Self.locale) {
                    text = transcript.text
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

    /// "Nói lại": replaces the text with a new recording (same draft).
    func speakAgain() async { await listen() }

    private func finishListening(errorCode: String?) {
        guard mode == .listening else { return }
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
