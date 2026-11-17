import AuthenticationServices
import Foundation
import UIKit

/// `GmailService`: Google consent in `ASWebAuthenticationSession` (iOS client + PKCE), then the one-time code goes
/// to `POST /v1/gmail/accounts`; the backend keeps the encrypted refresh token (API_GMAIL §2, D-151, D-310).
/// UIKit only for the presentation anchor (D-293: `UIApplication` inside Live services only).
final class LiveGmailService: GmailService {
    private let api: any APIClientProtocol
    private let clientID: String?

    init(api: any APIClientProtocol, clientID: String?) {
        self.api = api
        self.clientID = clientID
    }

    func accounts() async throws -> [GmailAccount] {
        try await api.gmailAccounts().accounts
    }

    func connect() async throws -> GmailAccount {
        guard let clientID else { throw ServiceError.unavailable(GmailErrorCode.notConfigured) }
        let request = GoogleConsentRequest(clientID: clientID)
        let callback = try await WebConsent().present(request.authorizationURL, scheme: request.callbackScheme)
        guard let code = request.code(from: callback) else {
            throw ServiceError.framework(code: GmailErrorCode.consentFailed)
        }
        return try await api.gmailConnect(GmailConnectRequest(code: code, codeVerifier: request.codeVerifier,
                                                              redirectUri: request.redirectURI)).account
    }

    func disconnect(accountId: String) async throws {
        try await api.gmailDisconnect(accountId: accountId)
    }
}

/// One consent sheet. Keeps the session alive until its completion handler runs.
@MainActor private final class WebConsent: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func present(_ url: URL, scheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: ServiceError.framework(code: GmailErrorCode.consentFailed))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {   // the handler is not called when `start()` fails
                continuation.resume(throwing: ServiceError.framework(code: GmailErrorCode.consentFailed))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            if let scene = scenes.first { return UIWindow(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }
}
