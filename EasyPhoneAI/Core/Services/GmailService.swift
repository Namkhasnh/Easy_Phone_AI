import CryptoKit
import Foundation

/// Gmail connection (API_GMAIL.md §2–§3, D-151, D-306, D-310). Live = Google consent in the system web sheet +
/// `/v1/gmail/accounts`; Mock for previews / tests (D-206). The app never holds a Google token.
protocol GmailService: Sendable {
    /// The connected account(s); MVP has at most one (D-306).
    func accounts() async throws -> [GmailAccount]
    /// Google consent → one-time code → backend. `CancellationError` when the user closes the sheet.
    func connect() async throws -> GmailAccount
    /// Idempotent (API_GMAIL §3.3).
    func disconnect(accountId: String) async throws
}

/// The Google consent request for an iOS OAuth client with PKCE (RFC 7636), and reading its callback.
/// Pure value logic so it is unit-tested without a browser.
struct GoogleConsentRequest: Sendable, Hashable {
    static let scopes = [
        "openid", "email",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.compose",
    ]

    let clientID: String
    let codeVerifier: String
    let state: String

    init(clientID: String, codeVerifier: String = Self.randomToken(), state: String = Self.randomToken()) {
        self.clientID = clientID
        self.codeVerifier = codeVerifier
        self.state = state
    }

    /// `com.googleusercontent.apps.<id>` — the URL scheme Google gives every iOS client.
    var callbackScheme: String {
        let prefix = "com.googleusercontent.apps."
        let id = clientID.hasSuffix(".apps.googleusercontent.com")
            ? String(clientID.dropLast(".apps.googleusercontent.com".count)) : clientID
        return prefix + id
    }

    var redirectURI: String { "\(callbackScheme):/oauth2redirect" }

    /// base64url(SHA-256(verifier)), no padding.
    var codeChallenge: String { Self.base64URL(Data(SHA256.hash(data: Data(codeVerifier.utf8)))) }

    var authorizationURL: URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),   // refresh token (API_GMAIL §2)
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// The one-time code from the callback. Wrong `state` or `error=…` (e.g. `access_denied`) → nil.
    func code(from callback: URL) -> String? {
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == state,
              items.first(where: { $0.name == "error" }) == nil,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code
    }

    /// 32 random bytes → 43 base64url chars (the PKCE minimum, RFC 7636 §4.1).
    static func randomToken() -> String {
        base64URL(Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Error codes the Gmail service throws as `ServiceError` (no HTTP involved).
enum GmailErrorCode {
    /// `GMAIL_CLIENT_ID` missing in `Config/Secrets.xcconfig`.
    static let notConfigured = "gmail.notConfigured"
    /// Google returned no code (denied, wrong state).
    static let consentFailed = "gmail.consentFailed"
}
