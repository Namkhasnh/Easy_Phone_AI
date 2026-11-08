import Foundation

/// Sign-in and session (ARCHITECTURE §4.1). Google only via Supabase Auth (D-283).
///
/// Error convention:
/// - user closed the Google sheet → `CancellationError` (S01 shows nothing);
/// - any other sign-in failure → `ServiceError.framework(code: "auth.signInFailed")`;
/// - no session → `ServiceError.unavailable("auth.notSignedIn")`.
protocol AuthService: Sendable {
    /// Current state first (`.signedIn` / `.signedOut`), then every change. Each access is a new stream.
    var sessionUpdates: AsyncStream<SessionState> { get }
    func signInWithGoogle() async throws
    /// Supabase access token (JWT) for `Authorization: Bearer`; `forceRefresh` after a `401` (ARCHITECTURE §10).
    func accessToken(forceRefresh: Bool) async throws -> String
    /// Always ends signed out on this device; drafts are kept (D-104).
    func signOut() async
}

enum AuthErrorCode {
    static let notSignedIn = "auth.notSignedIn"
    static let signInFailed = "auth.signInFailed"
}

/// OAuth callback registered in Supabase › Auth › URL Configuration (0.8) and in `Config/Info.plist` (D-283).
enum AuthRedirect {
    static let scheme = "vn.namkhanh.easyphone"
    static let url = URL(string: "\(scheme)://login-callback")!
}
