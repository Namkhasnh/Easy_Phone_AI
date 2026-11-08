import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("AuthService (D-283)")
struct AuthServiceTests {
    private struct Boom: Error {}

    @Test func signInThenSignOutPublishesEachState() async throws {
        let auth = MockAuthService()
        var updates = auth.sessionUpdates.makeAsyncIterator()
        #expect(await updates.next() == .signedOut)

        try await auth.signInWithGoogle()
        #expect(await updates.next() == .signedIn(userId: MockAuthService.userId))
        #expect(try await auth.accessToken(forceRefresh: false) == MockAuthService.accessToken)

        await auth.signOut()
        #expect(await updates.next() == .signedOut)
    }

    @Test func accessTokenWhenSignedOutThrowsNotSignedIn() async {
        let auth = MockAuthService()
        await #expect(throws: ServiceError.unavailable(AuthErrorCode.notSignedIn)) {
            try await auth.accessToken(forceRefresh: true)
        }
    }

    @Test func failedSignInKeepsSignedOut() async {
        let auth = MockAuthService(signInResult: .failure(ServiceError.framework(code: AuthErrorCode.signInFailed)))
        await #expect(throws: ServiceError.framework(code: AuthErrorCode.signInFailed)) {
            try await auth.signInWithGoogle()
        }
        #expect(auth.currentSession == .signedOut)
    }

    @Test func cancelledSignInKeepsSignedOut() async {
        let auth = MockAuthService(signInResult: .failure(CancellationError()))
        await #expect(throws: CancellationError.self) { try await auth.signInWithGoogle() }
        #expect(auth.currentSession == .signedOut)
    }

    @Test func newSubscriberGetsCurrentSessionFirst() async {
        let id = UUID()
        let auth = MockAuthService(initial: .signedIn(userId: id))
        var updates = auth.sessionUpdates.makeAsyncIterator()
        #expect(await updates.next() == .signedIn(userId: id))
    }

    @Test func redirectSchemeIsRegisteredInInfoPlist() throws {
        #expect(AuthRedirect.url.scheme == AuthRedirect.scheme)
        #expect(AuthRedirect.url.absoluteString == "vn.namkhanh.easyphone://login-callback")
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(AuthRedirect.scheme))
    }

    @Test func mockEnvironmentUsesMockAuth() {
        #expect(AppEnvironment.mock().auth is MockAuthService)
    }
}
