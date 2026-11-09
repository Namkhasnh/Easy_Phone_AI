import Foundation

/// System UI an executor needs the ViewModel to present (ARCHITECTURE §5.3). Recipients are device-only 🔒.
enum UIEffect: Sendable, Hashable {
    case composer(recipients: [String], body: String)
}

/// ARCHITECTURE §5.1 — what one execution produced; `TaskEngine` maps it to a `TaskEvent`.
enum ExecutionOutcome: Sendable, Hashable {
    case verified(evidence: String)          // → actionVerified (D-124: evidence required)
    case handedOff(note: String)             // → outcomeUnknownHandoff (D-102)
    case prepared                            // → dataPrepared (Phase 3)
    case needsUI(UIEffect)                   // engine keeps `processing`, ViewModel presents it
    case failed(code: String)                // → actionFailed, UI text from `error.<code>`
}

/// One executor per `TaskKind` (Calendar, Reminders, Call, SMS, Place, OCRConfirm — built in 1C/1D).
/// Executors do the permission check (§5.1 step 4), the idempotency lookup (D-105) and re-read verification.
@MainActor protocol StepExecutor: Sendable {
    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome
}

/// `MessageComposeResult` mapped by the composer bridge (1C.11); no MessageUI import here (D-015).
enum ComposerResult: Sendable, Hashable {
    case sent, cancelled, failed
}

/// Result of `TaskEngine.confirm` for the ViewModel.
enum ConfirmResult: Sendable, Hashable {
    /// Not confirmable (wrong state, validation issues, unknown step); nothing changed.
    case notAllowed
    /// Execution ended; the step is now in this state.
    case finished(TaskState)
    /// Step stays `processing`; present this UI, then call `composerFinished`.
    case needsUI(UIEffect)
}

/// Why a step cannot be confirmed right now (UI_SCREENS S04 disabled reasons).
enum ConfirmBlocker: Sendable, Hashable {
    case missing          // `review.disabled.missing`
    case ambiguity        // `review.disabled.ambiguity`
    case previousStep     // `review.disabled.previousStep`
    case notConfirmable   // not in `awaitingApproval` for another reason (e.g. already processing); no text
}
