import Foundation
import Observation

/// S01 Sign-in (UI_SCREENS S01, D-283). Forwards the tap to `AuthService`; RootView leaves S01 when
/// `sessionUpdates` reports `.signedIn`, so success needs no handling here.
@Observable @MainActor final class SignInViewModel {
    private(set) var isSigningIn = false
    private(set) var message: UserMessage?

    private let auth: any AuthService

    init(auth: any AuthService) {
        self.auth = auth
    }

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        message = nil
        defer { isSigningIn = false }
        do {
            try await auth.signInWithGoogle()
        } catch is CancellationError {
            // User closed the Google sheet: stay on S01 silently (AuthService contract).
        } catch {
            // TODO(decision): ServiceError code is `auth.signInFailed`, but UI_SCREENS has no
            // `error.auth.signInFailed` key; S01 defines its own `signIn.failed` (UI_SCREENS S01).
            message = UserMessage(key: "signIn.failed")
        }
    }
}
