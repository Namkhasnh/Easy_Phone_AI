import Foundation

/// Scripted `SpeechService` for previews and tests (D-206). Yields `script` in order, then finishes
/// (or throws `error` after the script, e.g. `.unavailable("speech.vi.unavailable")`).
@MainActor final class MockSpeechService: SpeechService {
    var script: [Transcript] = [
        Transcript(text: "Nhắc tôi", isFinal: false),
        Transcript(text: "Nhắc tôi 8 giờ sáng mai uống thuốc", isFinal: true, confidence: 0.9),
    ]
    var error: ServiceError?
    var audio: Data?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastLocale: Locale?

    /// `nonisolated` so `AppEnvironment.mock()` can build it off the main actor.
    nonisolated init() {}

    func start(locale: Locale) -> AsyncThrowingStream<Transcript, Error> {
        startCount += 1
        lastLocale = locale
        let script = script, error = error
        return AsyncThrowingStream { continuation in
            for transcript in script { continuation.yield(transcript) }
            continuation.finish(throwing: error)
        }
    }

    func stop() async { stopCount += 1 }

    func recordedAudio() async -> Data? { audio }
}
