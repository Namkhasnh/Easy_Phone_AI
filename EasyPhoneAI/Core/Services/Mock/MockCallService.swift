import Foundation
import Synchronization

/// Records `tel://` numbers instead of opening them (D-206).
final class MockCallService: CallService {
    private let state = Mutex<(calls: [String], types: [CallType], fails: Bool)>(([], [], false))

    init(fails: Bool = false) { state.withLock { $0.fails = fails } }

    var calls: [String] { state.withLock { $0.calls } }
    var types: [CallType] { state.withLock { $0.types } }

    func start(e164: String, type: CallType) async throws {
        try state.withLock { s in
            if s.fails { throw ServiceError.framework(code: "call.cannotOpen") }
            s.calls.append(e164)
            s.types.append(type)
        }
    }
}
