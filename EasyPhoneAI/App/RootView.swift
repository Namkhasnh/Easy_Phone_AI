import OSLog
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
        .task {
            for await quota in env.api.quotaUpdates {
                appState.apply(quota: quota)
            }
        }
        .task {
            for await screen in env.api.blockingUpdates {
                appState.blockingScreen = screen
            }
        }
        .fullScreenCover(isPresented: isBlocked) { blockingCover }
        .task(id: appState.session) {
            await loadAccount()
        }
    }

    /// API_CONTRACT §6.2: `/v1/me` on launch and after sign-in. Failures only log; UI keeps working.
    private func loadAccount() async {
        guard case .signedIn = appState.session else {
            appState.entitlement = nil
            return
        }
        do {
            appState.apply(me: try await env.api.me())
        } catch {
            let code = (error as? AppError)?.code ?? "cancelled"
            Self.logger.info("me failed: \(code, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "root")

    /// Root screen by session (UI_SCREENS §4): restoring → spinner, signed out → S01, signed in → S02.
    @ViewBuilder private var rootScreen: some View {
        switch appState.session {
        case .restoring:
            ProgressView()
        case .signedOut:
            SignInView(viewModel: SignInViewModel(auth: env.auth))
        case .signedIn:
            HomeView(viewModel: HomeViewModel(repository: env.drafts, localData: env.localData))
        }
    }

    /// UI_SCREENS §4: any 426 → S19, blocking. Never cleared by the user; only a newer build removes it.
    private var isBlocked: Binding<Bool> {
        Binding(get: { appState.blockingScreen != nil }, set: { _ in })
    }

    @ViewBuilder private var blockingCover: some View {
        switch appState.blockingScreen {
        case .clientOutdated(let minVersion):
            UpdateRequiredView(viewModel: UpdateRequiredViewModel(minVersion: minVersion))
        case nil:
            EmptyView()
        }
    }

    // TODO(spec): the other routes get their screens in their own items (1B–1F).
    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .review(let draftId):
            ReviewView(viewModel: ReviewViewModel(draftId: draftId, repository: env.drafts, engine: env.engine,
                                                       permissions: env.permissions,
                                                       snoozeMorningHour: env.localData.settings().snoozeMorningHour))
        case .conversation(let draftId):
            ConversationView(viewModel: ConversationViewModel(draftId: draftId, repository: env.drafts, speech: env.speech, api: env.api,
                                                              tts: env.tts, localData: env.localData,
                                                              permissions: env.permissions, engine: env.engine))
        case .calendarToday:
            CalendarTodayView(viewModel: CalendarTodayViewModel(calendar: env.calendar, permissions: env.permissions,
                                                                repository: env.drafts, engine: env.engine))
        case .reminders:
            RemindersView(viewModel: RemindersViewModel(reminders: env.reminders, permissions: env.permissions,
                                                        repository: env.drafts, engine: env.engine,
                                                        snoozeMorningHour: env.localData.settings().snoozeMorningHour))
        case .history:
            HistoryView(viewModel: HistoryViewModel(repository: env.drafts))
        case .settings:
            SettingsView(viewModel: SettingsViewModel(localData: env.localData, drafts: env.drafts, auth: env.auth,
                                                      tts: env.tts, permissions: env.permissions))
        default:
            EmptyView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .environment(Router())
        .environment(\.appEnv, .mock())
        .modelContainer(try! ModelContainerFactory.make(inMemory: true))   // preview only
}
