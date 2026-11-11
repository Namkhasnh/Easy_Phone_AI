import SwiftData
import SwiftUI

@main struct EasyPhoneApp: App {
    @State private var appState = AppState()
    @State private var router = Router()
    @State private var handoff: HandoffPromptCoordinator
    /// ARCHITECTURE §5.4 (D-125): once per process, at the first appearance (= first `.active`).
    private let launchVerifier: LaunchVerifier
    private let env: AppEnvironment
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.make()
        } catch {
            // TODO(spec): store open failure (corrupt / migration) has no screen; drafts must never be lost (D-104).
            fatalError("SwiftData container failed: \(error)")
        }
        let env = AppEnvironment.live(container: modelContainer)
        self.env = env
        _handoff = State(initialValue: HandoffPromptCoordinator(repository: env.drafts, engine: env.engine))
        launchVerifier = LaunchVerifier(repository: env.drafts, engine: env.engine)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(router)
                .environment(handoff)
                .environment(\.appEnv, env)
                .task { await launchVerifier.runOnce() }
        }
        .modelContainer(modelContainer)
    }
}
