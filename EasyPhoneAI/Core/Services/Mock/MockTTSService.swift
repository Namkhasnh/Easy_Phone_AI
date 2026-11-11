import Foundation

/// Records what would be spoken (D-206). `speak` returns at once.
@MainActor final class MockTTSService: TTSService {
    private(set) var spoken: [(text: String, rate: Double)] = []
    private(set) var stopCount = 0

    /// `nonisolated` so `AppEnvironment.mock()` can build it off the main actor.
    nonisolated init() {}

    func speak(_ text: String, rate: Double) async {
        spoken.append((text, rate))
    }

    func stop() { stopCount += 1 }
}
