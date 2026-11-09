import SwiftData
import SwiftUI

@main struct EasyPhoneApp: App {
    @State private var appState = AppState()
    @State private var router = Router()
    private let env: AppEnvironment
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.make()
        } catch {
            // TODO(spec): store open failure (corrupt / migration) has no screen; drafts must never be lost (D-104).
            fatalError("SwiftData container failed: \(error)")
        }
        env = .live(container: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(router)
                .environment(\.appEnv, env)
        }
        .modelContainer(modelContainer)
    }
}
