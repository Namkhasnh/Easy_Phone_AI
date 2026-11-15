import Foundation
import OSLog

/// ARCHITECTURE §5.4, D-125: on the first `.active` of the process, every step left `processing` (app killed while it
/// ran, e.g. SMS composer open) → `interrupted` → `unknown`; then every `unknown` step is checked for evidence
/// (DATA_MODEL §3.5) → `succeeded`, or stays `unknown`. Never re-runs an action (D-105).
@MainActor final class LaunchVerifier {
    private let repository: any TaskRepository
    private let engine: TaskEngine
    private var didRun = false
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "launchVerifier")

    init(repository: any TaskRepository, engine: TaskEngine) {
        self.repository = repository
        self.engine = engine
    }

    /// Runs once per process; later calls do nothing.
    func runOnce() async {
        guard !didRun else { return }
        didRun = true
        for (draftId, step) in repository.steps(in: [.processing]) {
            guard let draft = repository.draft(draftId) else { continue }
            engine.interrupt(stepId: step.id, in: draft)
        }
        var verified = 0
        let unknown = repository.steps(in: [.unknown])
        for (draftId, step) in unknown {
            guard let draft = repository.draft(draftId) else { continue }
            if await engine.verifyOnLaunch(stepId: step.id, in: draft) { verified += 1 }
        }
        logger.info("launch verification: \(unknown.count, privacy: .public) unknown, \(verified, privacy: .public) verified")
    }
}
