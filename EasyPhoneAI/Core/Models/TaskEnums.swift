import Foundation

// DATA_MODEL §1. Raw values are contracts (Swift, JSON schema, Pydantic, prompts) — rename = change all in one commit.
// Unknown raw values fail decoding (no `.unknown` case is specified for these enums).

/// DATA_MODEL §1.1. Phase 2/3 cases (`emailReply`, `ride`, `food`) exist for decoding only (D-140, D-150).
enum TaskKind: String, Codable, Sendable, Hashable, CaseIterable {
    case calendarEvent, reminder, call, sms, place, ocr
    case emailReply
    case ride, food

    /// DATA_MODEL §1.2 "Valid pairs". Any other `(kind, operation)` → invalid draft.
    var allowedOperations: Set<TaskOperation> {
        switch self {
        case .calendarEvent: [.create, .update, .delete]
        case .reminder: [.create, .update, .delete, .complete, .snooze]
        case .call, .sms: [.open]
        case .place: [.create, .open]
        case .ocr, .emailReply: [.create]
        case .ride, .food: [.prepare]
        }
    }

    func allows(_ operation: TaskOperation) -> Bool { allowedOperations.contains(operation) }
}

/// DATA_MODEL §1.2 — a step's verb.
enum TaskOperation: String, Codable, Sendable, Hashable, CaseIterable {
    case create, update, delete, complete, snooze, open, prepare
}

/// DATA_MODEL §1.3 (D-121, exact list — do not add states).
enum TaskState: String, Codable, Sendable, Hashable, CaseIterable {
    case draft, needsInfo, awaitingApproval, processing, prepared, handedOff,
         succeeded, unknown, failed, cancelled, userMarkedDone

    /// D-122. `failed` is final but still retryable / cancellable (D-243).
    var isFinal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .userMarkedDone: true
        default: false
        }
    }

    /// D-244. `failed` is final but **not** closed (still needs the user).
    var isClosed: Bool {
        switch self {
        case .succeeded, .cancelled, .userMarkedDone: true
        default: false
        }
    }
}

/// DATA_MODEL §1.4 — input to the state machine (D-123).
enum TaskEvent: String, Codable, Sendable, Hashable, CaseIterable {
    case missingRequiredField, allRequiredFilled, userConfirmed, userEdited, actionVerified,
         outcomeUnknownHandoff, dataPrepared, externalServiceOpened, actionFailed, interrupted,
         userMarkedDone, userCancelled, retry
}

/// DATA_MODEL §1.6 — how a field's `value` string is encoded. `contactRef` / `placeRef` are 🔒 (D-056).
enum FieldType: String, Codable, Sendable, Hashable, CaseIterable {
    case text, longText, dateTime, date, durationMinutes, bool, phone,
         contactRef, placeRef, address, coordinate, enumChoice
}
