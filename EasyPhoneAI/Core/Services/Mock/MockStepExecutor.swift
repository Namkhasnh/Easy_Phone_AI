import Foundation

/// Returns a fixed outcome and records the steps it was asked to execute (previews + tests, D-206).
@MainActor final class MockStepExecutor: StepExecutor {
    var outcome: ExecutionOutcome
    private(set) var executed: [TaskStep] = []

    init(outcome: ExecutionOutcome) { self.outcome = outcome }

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        executed.append(step)
        return outcome
    }
}
