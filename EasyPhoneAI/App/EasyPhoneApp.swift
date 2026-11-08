import SwiftUI

@main struct EasyPhoneApp: App {
    @State private var appState = AppState()
    @State private var router = Router()
    private let env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(router)
                .environment(\.appEnv, env)
        }
    }
}
