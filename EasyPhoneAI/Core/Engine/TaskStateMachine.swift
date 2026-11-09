import Foundation
import os

/// Extra input that distinguishes rows of the transition table (DATA_MODEL §1.5).
struct TransitionContext: Sendable, Hashable {
    /// SMS composer returned `.cancelled` (D-222): `processing` + `userCancelled` → `awaitingApproval`.
    var composerDismissed: Bool = false

    static let `default` = TransitionContext()
}

/// DATA_MODEL §1.5 — implemented exactly; any pair not in the table is illegal (D-123).
/// Pure: no state is stored here. Only `TaskEngine` applies the result to `TaskStep.state`.
enum TaskStateMachine {
    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "stateMachine")

    /// Returns the next state, or `nil` (+ warning log) when the transition is illegal.
    static func transition(
        _ state: TaskState,
        _ event: TaskEvent,
        context: TransitionContext = .default
    ) -> TaskState? {
        let next = nextState(state, event, context: context)
        if next == nil {
            logger.warning("illegal transition \(state.rawValue, privacy: .public) + \(event.rawValue, privacy: .public)")
        }
        return next
    }

    private static func nextState(_ state: TaskState, _ event: TaskEvent, context: TransitionContext) -> TaskState? {
        switch (state, event) {
        case (.draft, .missingRequiredField): .needsInfo
        case (.draft, .allRequiredFilled), (.needsInfo, .allRequiredFilled): .awaitingApproval
        case (.needsInfo, .userEdited): .needsInfo                       // re-validate → may emit allRequiredFilled
        case (.awaitingApproval, .userConfirmed): .processing
        case (.awaitingApproval, .userEdited): .awaitingApproval         // engine clears approvedSnapshotHash (D-101)
        case (.awaitingApproval, .missingRequiredField): .needsInfo
        case (.processing, .actionVerified): .succeeded
        case (.processing, .outcomeUnknownHandoff): .handedOff
        case (.processing, .dataPrepared): .prepared
        case (.prepared, .externalServiceOpened): .handedOff
        case (.processing, .actionFailed): .failed
        case (.processing, .interrupted): .unknown
        case (.unknown, .actionVerified): .succeeded                     // launch verification found evidence
        case (.unknown, .retry): .awaitingApproval                       // idempotency check first (D-243)
        case (.handedOff, .userMarkedDone), (.unknown, .userMarkedDone): .userMarkedDone
        case (.prepared, .userMarkedDone): .userMarkedDone               // copy-guide path (D-242)
        case (.failed, .retry): .awaitingApproval                        // idempotency check first (D-105)
        case (.failed, .userCancelled): .cancelled                       // D-243
        case (.failed, .userMarkedDone): .userMarkedDone                 // D-243
        case (.succeeded, .userEdited): .awaitingApproval                // edit = new update action
        case (.processing, .userCancelled) where context.composerDismissed: .awaitingApproval  // D-222
        case (_, .userCancelled) where !state.isFinal: .cancelled        // any non-final
        default: nil
        }
    }
}
