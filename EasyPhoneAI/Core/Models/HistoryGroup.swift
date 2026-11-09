import Foundation

/// DATA_MODEL §8 History group; raw value = key suffix `history.group.<raw>` (UI_SCREENS S14).
/// `allCases` order = S14 fixed order = priority (needsYou > waiting > done > cancelled).
enum HistoryGroup: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case needsYou, waiting, done, cancelled

    var titleKey: String { "history.group.\(rawValue)" }

    static func < (a: HistoryGroup, b: HistoryGroup) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

extension TaskState {
    /// DATA_MODEL §8 table, column "History group".
    var historyGroup: HistoryGroup {
        switch self {
        case .draft, .needsInfo, .awaitingApproval, .prepared, .unknown, .failed: .needsYou
        case .processing, .handedOff: .waiting
        case .succeeded, .userMarkedDone: .done
        case .cancelled: .cancelled
        }
    }
}

extension TaskDraft {
    /// D-244: first step by `order` that is not closed and not `handedOff`; none → the last step.
    var currentStep: TaskStep? {
        let ordered = steps.sorted { $0.order < $1.order }
        return ordered.first { !$0.state.isClosed && $0.state != .handedOff } ?? ordered.last
    }

    /// D-244: every step closed (`succeeded`, `cancelled`, `userMarkedDone`).
    // TODO(spec): a draft with no steps (e.g. "Chưa hỗ trợ") is unspecified; treated as not closed, group needsYou.
    var isClosed: Bool { !steps.isEmpty && steps.allSatisfy(\.state.isClosed) }

    /// DATA_MODEL §8: the highest-priority group among the steps.
    var overallStatus: HistoryGroup { steps.map(\.state.historyGroup).min() ?? .needsYou }

    /// "Việc chưa xong" (Home list, widget count, toasts, D-244).
    var isUnfinished: Bool { overallStatus == .needsYou || overallStatus == .waiting }

    /// "{done}/{total} bước" on S14: done = closed steps (D-244).
    var closedStepCount: Int { steps.filter(\.state.isClosed).count }
}
