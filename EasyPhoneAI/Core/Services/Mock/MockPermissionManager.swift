import Foundation
import Synchronization

/// Scripted `PermissionManager` for previews and tests (D-206). Unknown capabilities start `granted` so previews
/// never show S18 unless asked; `request` turns `notDetermined` into `answer` and records the call.
final class MockPermissionManager: PermissionManager {
    private struct State {
        var statuses: [Capability: PermissionStatus]
        var answer: PermissionStatus
        var requested: [Capability] = []
    }

    private let state: Mutex<State>

    init(_ statuses: [Capability: PermissionStatus] = [:], answer: PermissionStatus = .granted) {
        state = Mutex(State(statuses: statuses, answer: answer))
    }

    /// Capabilities passed to `request`, in order.
    var requested: [Capability] { state.withLock { $0.requested } }

    func set(_ capability: Capability, _ status: PermissionStatus) {
        state.withLock { $0.statuses[capability] = status }
    }

    func status(_ capability: Capability) -> PermissionStatus {
        state.withLock { $0.statuses[capability] ?? .granted }
    }

    func request(_ capability: Capability) async -> PermissionStatus {
        state.withLock { s in
            s.requested.append(capability)
            let current = s.statuses[capability] ?? .granted
            guard current == .notDetermined else { return current }   // like iOS: asked only once
            s.statuses[capability] = s.answer
            return s.answer
        }
    }
}
