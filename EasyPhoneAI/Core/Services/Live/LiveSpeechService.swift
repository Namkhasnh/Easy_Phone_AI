import AVFoundation
import OSLog
import Speech
import Synchronization

/// `SFSpeechRecognizer` (vi-VN) **on device only** (D-055, DECISIONS §2.1) + an m4a copy of the audio for the
/// `/v1/transcribe` fallback (ARCHITECTURE §4.3). The ViewModel decides on the fallback; this service never calls the backend.
/// Recognizer missing / not on-device for the locale → records anyway, and the stream ends with
/// `speech.vi.unavailable` on `stop()` so the ViewModel can offer the keyboard or upload `recordedAudio()`.
@MainActor final class LiveSpeechService: SpeechService {
    private struct Session {
        let id: UUID
        let engine: AVAudioEngine
        let sink: TapSink
        let recognitionTask: SFSpeechRecognitionTask?
        let continuation: AsyncThrowingStream<Transcript, Error>.Continuation
        let limitTask: Task<Void, Never>
    }

    private var session: Session?
    private var lastAudioURL: URL?

    init() {}

    func start(locale: Locale) -> AsyncThrowingStream<Transcript, Error> {
        let id = UUID()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in await self?.end(id) }       // only this stream's session, never a newer one
            }
            Task { @MainActor in
                do {
                    try await self.begin(id: id, locale: locale, continuation: continuation)
                } catch {
                    Self.logger.info("speech start failed: \((error as? ServiceError)?.code ?? "speech.failed", privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func stop() async {
        if let id = session?.id { await end(id) }
    }

    func recordedAudio() async -> Data? {
        guard let url = lastAudioURL else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Session

    private func begin(id: UUID, locale: Locale,
                       continuation: AsyncThrowingStream<Transcript, Error>.Continuation) async throws {
        await stop()
        try await Self.ensurePermissions()

        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audio.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {   // no input device (e.g. Simulator without mic)
            try? audio.setActive(false)
            throw ServiceError.framework(code: "speech.failed")
        }

        if let old = lastAudioURL { try? FileManager.default.removeItem(at: old) }   // keep only the last session's audio
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(id.uuidString).m4a")
        let file = try AVAudioFile(forWriting: url,
                                   settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                              AVSampleRateKey: format.sampleRate,
                                              AVNumberOfChannelsKey: format.channelCount],
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        lastAudioURL = url

        // On device only: audio never leaves the phone through Apple's servers (D-055).
        let recognizer = SFSpeechRecognizer(locale: locale)
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        if let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            r.requiresOnDeviceRecognition = true
            r.addsPunctuation = true
            r.taskHint = .dictation
            request = r
            task = recognizer.recognitionTask(with: r, resultHandler: Self.resultHandler(continuation))
        } else {
            Self.logger.info("speech: on-device recognizer unavailable for locale")
        }

        let sink = TapSink(request: request, file: file)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(sink))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            task?.cancel()
            try? audio.setActive(false)
            throw ServiceError.framework(code: "speech.failed")
        }

        let limit = Task { @MainActor [weak self] in
            try? await Task.sleep(for: SpeechLimits.maxDuration)     // API_CONTRACT §7.4: ≤ 60 s
            if !Task.isCancelled { await self?.end(id) }
        }
        session = Session(id: id, engine: engine, sink: sink, recognitionTask: task,
                          continuation: continuation, limitTask: limit)
    }

    /// Stops recording; the recognizer then delivers its final result and the handler finishes the stream.
    private func end(_ id: UUID) async {
        guard let s = session, s.id == id else { return }
        session = nil
        s.limitTask.cancel()
        s.engine.stop()
        s.engine.inputNode.removeTap(onBus: 0)
        s.sink.close()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let task = s.recognitionTask else {
            s.continuation.finish(throwing: ServiceError.unavailable("speech.vi.unavailable"))
            return
        }
        s.sink.endAudio()
        // TODO(spec): no time limit for the final result is specified; the stream is closed after 3 s if none arrives.
        let continuation = s.continuation
        Task {
            try? await Task.sleep(for: .seconds(3))
            task.finish()
            continuation.finish()                                   // no-op if the final already finished it
        }
    }

    // MARK: - Permissions

    /// Never prompts: S03 shows the S18 explainer and asks through `PermissionManager` first (D-185).
    private static func ensurePermissions() async throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw ServiceError.permissionDenied(.microphone)
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw ServiceError.permissionDenied(.speech)
        }
    }

    // MARK: - Callbacks (built nonisolated: they run on audio / Speech threads, never on the main actor)

    nonisolated private static func tapBlock(_ sink: TapSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.append(buffer) }
    }

    nonisolated private static func resultHandler(
        _ continuation: AsyncThrowingStream<Transcript, Error>.Continuation
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        let lastText = Mutex("")
        return { result, error in
            if let result {
                // An empty final after `endAudio` must not replace the words already heard.
                let heard = result.bestTranscription.formattedString
                let text = heard.isEmpty ? lastText.withLock { $0 } : heard
                if !heard.isEmpty { lastText.withLock { $0 = heard } }
                let scores = result.bestTranscription.segments.map(\.confidence)
                continuation.yield(Transcript(text: text, isFinal: result.isFinal,
                                              confidence: result.isFinal ? Transcript.averageConfidence(scores) : nil))
                if result.isFinal { continuation.finish() }
            } else if let error {
                // "No speech detected" and similar end here: deliver what we have as final; the ViewModel shows
                // `conv.speech.empty` for an empty text. Only the numeric code is logged (D-059).
                logger.info("speech recognizer ended: \((error as NSError).code, privacy: .public)")
                continuation.yield(Transcript(text: lastText.withLock { $0 }, isFinal: true))
                continuation.finish()
            }
        }
    }

    nonisolated private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "speech")
}

/// Receives audio buffers on the audio render thread: feeds the recognizer and writes the m4a copy.
/// `@unchecked Sendable`: the request and file are touched only by the tap thread while recording, then by `end()`
/// on the main actor after `removeTap` has returned (no more tap calls); the lock guards the hand-over.
private final class TapSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var file: AVAudioFile?

    init(request: SFSpeechAudioBufferRecognitionRequest?, file: AVAudioFile) {
        self.request = request
        self.file = file
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            request?.append(buffer)
            try? file?.write(from: buffer)
        }
    }

    func endAudio() {
        lock.withLock { request?.endAudio() }
    }

    /// Flushes the m4a; later buffers are dropped.
    func close() {
        lock.withLock {
            file?.close()
            file = nil
        }
    }
}
