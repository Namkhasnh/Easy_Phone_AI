import Foundation

/// Speech-to-text, on device first (ARCHITECTURE §4.3, D-055). `@MainActor` because it owns the audio session (§8).
/// Errors are `ServiceError` with stable codes (D-249): `speech.vi.unavailable`, `permission.microphone.denied`,
/// `permission.speech.denied`, `speech.failed`.
@MainActor protocol SpeechService: AnyObject, Sendable {
    /// Starts listening. Yields partial transcripts, then one final, then finishes.
    /// The stream also finishes (final first) after `stop()` or after `maxDuration`.
    func start(locale: Locale) -> AsyncThrowingStream<Transcript, Error>
    func stop() async
    /// The last session's audio as m4a (AAC) for the `/v1/transcribe` fallback (API_CONTRACT §7.4); `nil` if none.
    func recordedAudio() async -> Data?
}

enum SpeechLimits {
    /// `/v1/transcribe` accepts ≤ 60 s of audio (API_CONTRACT §7.4), so a session never records longer.
    static let maxDuration: Duration = .seconds(60)
}
