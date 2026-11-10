import Foundation

/// DATA_MODEL §3.1. Value type stored inside `TaskDraft.steps`.
/// Only `TaskEngine` writes `state` (D-123), always through `transition(_:_:context:)` (1A.4).
struct TaskStep: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var order: Int                         // 0-based execution order within the draft
    var kind: TaskKind
    var operation: TaskOperation
    var state: TaskState
    var fields: [Field]                    // order = catalog order (§4)
    var targetRef: String?                 // 🔒 existing object for update/delete/complete/snooze
    var approvedSnapshotHash: String?      // §3.4; set on userConfirmed, cleared on entering awaitingApproval
    var resultEvidence: String?            // 🔒 required for succeeded (D-124), §3.5
    var handoffNote: String?               // Vietnamese: what the user still must do
    var handoffPromptShown: Bool           // D-242 return prompt already asked for this hand-off
    var errorMessage: String?              // Vietnamese, user-facing; no stack traces
    var errorCode: String?                 // `<domain>.<reason>` (D-249)
    var attempt: Int                       // incremented on each processing entry (idempotency)
    var stateChangedAt: Date
    var history: [StateChange]             // append-only audit; cap 50 (enforced by TaskEngine, 1A.8)

    init(
        id: UUID = UUID(),
        order: Int,
        kind: TaskKind,
        operation: TaskOperation,
        state: TaskState = .draft,
        fields: [Field] = [],
        targetRef: String? = nil,
        approvedSnapshotHash: String? = nil,
        resultEvidence: String? = nil,
        handoffNote: String? = nil,
        handoffPromptShown: Bool = false,
        errorMessage: String? = nil,
        errorCode: String? = nil,
        attempt: Int = 0,
        stateChangedAt: Date = .now,
        history: [StateChange] = []
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.operation = operation
        self.state = state
        self.fields = fields
        self.targetRef = targetRef
        self.approvedSnapshotHash = approvedSnapshotHash
        self.resultEvidence = resultEvidence
        self.handoffNote = handoffNote
        self.handoffPromptShown = handoffPromptShown
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.attempt = attempt
        self.stateChangedAt = stateChangedAt
        self.history = history
    }

    func field(_ id: String) -> Field? { fields.first { $0.id == id } }
}

/// DATA_MODEL §3.1.
struct StateChange: Codable, Sendable, Hashable {
    var from: TaskState
    var to: TaskState
    var event: TaskEvent
    var at: Date
}
