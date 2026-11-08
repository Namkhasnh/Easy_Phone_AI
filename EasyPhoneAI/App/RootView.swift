import SwiftUI

/// Root navigation (ARCHITECTURE §2.2): one `NavigationStack` bound to `Router.path`.
struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            // TODO(spec): root screen chosen by AppState.session (S01 sign-in in 0.10, S02 Home in 1B.1).
            ProgressView()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
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
}
