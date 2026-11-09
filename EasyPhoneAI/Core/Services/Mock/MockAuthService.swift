import Foundation
import Synchronization

/// In-memory `AuthService` for previews and tests (D-206). Never touches the network or Keychain.
final class MockAuthService: AuthService {
    /// = `userId` in the contract fixtures (API_CONTRACT §6.2 example).
    static let userId = UUID(uuidString: "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11")!
    static let accessToken = "mock-access-token"

    private struct State {
        var session: SessionState
        var continuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]
    }

    private let state: Mutex<State>
    private let signInResult: Result<UUID, any Error>

    init(initial: SessionState = .signedOut,
         signInResult: Result<UUID, any Error> = .success(MockAuthService.userId)) {
        state = Mutex(State(session: initial))
        self.signInResult = signInResult
    }

    var currentSession: SessionState { state.withLock { $0.session } }

    var sessionUpdates: AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionState.self)
        let id = UUID()
        let current = state.withLock { s in
            s.continuations[id] = continuation
            return s.session
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        }
        continuation.yield(current)
        return stream
    }

    func signInWithGoogle() async throws {
        let userId = try signInResult.get()
        publish(.signedIn(userId: userId))
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        guard case .signedIn = currentSession else {
            throw ServiceError.unavailable(AuthErrorCode.notSignedIn)
        }
        return Self.accessToken
    }

    func signOut() async {
        publish(.signedOut)
    }

    private func publish(_ session: SessionState) {
        let continuations = state.withLock { s in
            s.session = session
            return Array(s.continuations.values)
        }
        for continuation in continuations { continuation.yield(session) }
    }
}
