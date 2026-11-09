import Foundation

/// DATA_MODEL §8 state → UI mapping (label key + SF Symbol). Color is decoration only (D-183).
extension TaskState {
    /// `state.<raw>`; `prepared` takes `{service}`, `handedOff` takes `{app}` (`%@`).
    var labelKey: String { "state.\(rawValue)" }

    var symbolName: String {
        switch self {
        case .draft: "square.and.pencil"
        case .needsInfo: "questionmark.circle"
        case .awaitingApproval: "hand.raised"
        case .processing: "hourglass"
        case .prepared: "tray.full"
        case .handedOff: "arrow.up.forward.app"
        case .unknown: "exclamationmark.circle"
        case .succeeded: "checkmark.circle"
        case .userMarkedDone: "checkmark.seal"
        case .failed: "xmark.octagon"
        case .cancelled: "minus.circle"
        }
    }
}
