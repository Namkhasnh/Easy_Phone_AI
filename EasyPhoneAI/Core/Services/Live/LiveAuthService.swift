import Auth
import AuthenticationServices
import Foundation

/// `AuthService` backed by the Supabase Swift SDK (`Auth` product only, D-017, D-283).
/// The only file in the app that imports `Auth` (D-015). Session is stored in the Keychain.
final class LiveAuthService: AuthService {
    private let client: AuthClient

    init(config: AppConfig) {
        guard let supabaseURL = config.supabaseURL, let key = config.supabaseAnonKey else {
            fatalError("LiveAuthService: SUPABASE_URL / SUPABASE_ANON_KEY are empty. Fill Config/Secrets.xcconfig (see Secrets.example.xcconfig).")
        }
        client = AuthClient(
            url: supabaseURL.appending(path: "auth/v1"),
            headers: ["apikey": key],
            flowType: .pkce,
            redirectToURL: AuthRedirect.url,
            localStorage: KeychainLocalStorage(),
            logger: nil
        )
    }

    var sessionUpdates: AsyncStream<SessionState> {
        let changes = client.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes {
                    continuation.yield(Self.sessionState(change.session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signInWithGoogle() async throws {
        do {
            _ = try await client.signInWithOAuth(provider: .google, redirectTo: AuthRedirect.url)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceError.framework(code: AuthErrorCode.signInFailed)
        }
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        do {
            let session = forceRefresh ? try await client.refreshSession() : try await client.session
            return session.accessToken
        } catch {
            throw ServiceError.unavailable(AuthErrorCode.notSignedIn)
        }
    }

    func signOut() async {
        do {
            try await client.signOut()
        } catch {
            // Offline or server error: still sign out on this device (drafts stay, D-104).
            try? await client.signOut(scope: .local)
        }
    }

    private static func sessionState(_ session: Session?) -> SessionState {
        guard let session else { return .signedOut }
        return .signedIn(userId: session.user.id)
    }
}
