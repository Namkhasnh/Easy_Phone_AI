import SwiftData
import SwiftUI

/// Root navigation (ARCHITECTURE §2.2): one `NavigationStack` bound to `Router.path`.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.appEnv) private var env

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            rootScreen
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .task {
            for await session in env.auth.sessionUpdates {
                appState.session = session
            }
        }
    }

    /// Root screen by session (UI_SCREENS §4): restoring → spinner, signed out → S01, signed in → S02.
    @ViewBuilder private var rootScreen: some View {
        switch appState.session {
        case .restoring:
            ProgressView()
        case .signedOut:
            SignInView(viewModel: SignInViewModel(auth: env.auth))
        case .signedIn(let userId):
            // TODO(spec): S02 Home replaces this in 1B.1; until then show the signed-in user id (EXIT 0 check).
            Text(verbatim: userId.uuidString)
                .font(Tokens.Fonts.body)
                .textSelection(.enabled)
        }
    }

    // TODO(spec): each route gets its screen in its own item (S04 1A.11, S14 1A.13, S15 1A.14, …).
    @ViewBuilder private func destination(_ route: Route) -> some View {
        EmptyView()
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .environment(Router())
        .environment(\.appEnv, .mock())
        .modelContainer(try! ModelContainerFactory.make(inMemory: true))   // preview only
}
