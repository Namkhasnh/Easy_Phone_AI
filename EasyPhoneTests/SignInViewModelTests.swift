import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("S01 SignInViewModel (D-283, D-265)")
@MainActor
struct SignInViewModelTests {
    @Test func successSignsInWithoutMessage() async {
        let auth = MockAuthService()
        let viewModel = SignInViewModel(auth: auth)

        await viewModel.signIn()

        #expect(auth.currentSession == .signedIn(userId: MockAuthService.userId))
        #expect(viewModel.message == nil)
        #expect(viewModel.isSigningIn == false)
    }

    @Test func cancelledSignInIsSilent() async {
        let auth = MockAuthService(signInResult: .failure(CancellationError()))
        let viewModel = SignInViewModel(auth: auth)

        await viewModel.signIn()

        #expect(auth.currentSession == .signedOut)
        #expect(viewModel.message == nil)
        #expect(viewModel.isSigningIn == false)
    }

    @Test func failedSignInShowsSignInFailedKey() async {
        let auth = MockAuthService(signInResult: .failure(ServiceError.framework(code: AuthErrorCode.signInFailed)))
        let viewModel = SignInViewModel(auth: auth)

        await viewModel.signIn()

        #expect(auth.currentSession == .signedOut)
        #expect(viewModel.message == UserMessage(key: "signIn.failed"))
        #expect(viewModel.isSigningIn == false)
    }

    @Test func everyS01KeyExistsInStringCatalog() {
        let keys = ["signIn.title", "signIn.tagline", "signIn.reason", "signIn.google",
                    "signIn.legal", "signIn.failed", "signIn.sessionExpired"]
        // Hosted unit tests: `Bundle.main` is the app (test-host-target).
        for key in keys {
            let value = Bundle.main.localizedString(forKey: key, value: "∅", table: nil)
            #expect(value != "∅" && value != key, "missing \(key)")
        }
    }
}
