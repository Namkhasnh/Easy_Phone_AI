import Foundation

/// Records the Live Activity calls (D-206).
@MainActor final class MockGuideProgressService: GuideProgressService {
    private(set) var shown: [GuideProgress] = []
    private(set) var endCount = 0

    /// `nonisolated` so `AppEnvironment.mock()` can build it off the main actor.
    nonisolated init() {}

    func show(_ progress: GuideProgress) { shown.append(progress) }
    func end() { endCount += 1 }
}
