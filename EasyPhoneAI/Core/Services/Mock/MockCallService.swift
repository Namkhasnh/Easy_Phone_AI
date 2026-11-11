import Foundation
import Synchronization

/// Records `tel://` numbers instead of opening them (D-206).
final class MockCallService: CallService {
    private let state = Mutex<(calls: [String], fails: Bool)>(([], false))

    init(fails: Bool = false) { state.withLock { $0.fails = fails } }

    var calls: [String] { state.withLock { $0.calls } }

    func start(e164: String) async throws {
        try state.withLock { s in
            if s.fails { throw ServiceError.framework(code: "call.cannotOpen") }
            s.calls.append(e164)
        }
    }
}
