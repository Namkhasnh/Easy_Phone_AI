import AppIntents
import SwiftData
import SwiftUI

@main struct EasyPhoneApp: App {
    @State private var appState: AppState
    @State private var router = Router()
    @State private var handoff: HandoffPromptCoordinator
    /// ARCHITECTURE §5.4 (D-125): once per process, at the first appearance (= first `.active`).
    private let launchVerifier: LaunchVerifier
    private let env: AppEnvironment
    private let modelContainer: ModelContainer

    init() {
        // `StartListeningIntent` sets the flag on this same AppState (D-172).
        let state = AppState()
        _appState = State(initialValue: state)
        ListenRequests.onRequest = { state.startListeningRequested = true }
        // XCUITest (ARCHITECTURE §13): `-uiTestScenario <name>` → mocks + in-memory store, never real device data.
        let scenario = MockScenario.fromLaunchArguments()
        let options = MockScenario.UITestOptions.fromLaunchArguments()
        do {
            modelContainer = scenario != nil && options.disk
                ? try ModelContainerFactory.makeUITestStore(reset: options.resetStore)
                : try ModelContainerFactory.make(inMemory: scenario != nil)
        } catch {
            // TODO(spec): store open failure (corrupt / migration) has no screen; drafts must never be lost (D-104).
            fatalError("SwiftData container failed: \(error)")
        }
        let stored: (any TaskRepository)? = options.disk ? LiveTaskRepository(container: modelContainer) : nil
        let env = scenario.map { AppEnvironment.mock($0, options: options, drafts: stored) }
            ?? AppEnvironment.live(container: modelContainer)
        self.env = env
        KhoaiPanel.env = env                                     // D-325: "Hỏi Khoai" runs in this process
        KhoaiPanel.appState = state
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
                .onOpenURL { url in                                   // widgets: easyphone://listen (D-172)
                    if url.scheme == "easyphone", url.host() == "listen" { appState.startListeningRequested = true }
                }
        }
        .modelContainer(modelContainer)
    }
}
