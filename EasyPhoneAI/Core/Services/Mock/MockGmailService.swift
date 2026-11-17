import Foundation
import Synchronization

/// In-memory `GmailService` for previews and tests (D-206). "Dữ liệu mẫu" address only (D-189).
final class MockGmailService: GmailService {
    static let sample = GmailAccount(accountId: "gma_01JD0000000000000000000000", email: "khoai.demo@gmail.com",
                                     status: .connected)

    private let state: Mutex<[GmailAccount]>
    /// nil → connects `sample`; `CancellationError` = the user closed the Google sheet.
    private let connectError: (any Error & Sendable)?
    private let disconnects = Mutex<[String]>([])

    init(accounts: [GmailAccount] = [], connectError: (any Error & Sendable)? = nil) {
        state = Mutex(accounts)
        self.connectError = connectError
    }

    /// Ids passed to `disconnect` so far.
    var disconnectCalls: [String] { disconnects.withLock { $0 } }

    func accounts() async throws -> [GmailAccount] { state.withLock { $0 } }

    func connect() async throws -> GmailAccount {
        if let connectError { throw connectError }
        let account = Self.sample
        state.withLock { $0 = [account] }                 // one account (D-306)
        return account
    }

    func disconnect(accountId: String) async throws {
        disconnects.withLock { $0.append(accountId) }
        state.withLock { $0.removeAll { $0.accountId == accountId } }
    }
}
