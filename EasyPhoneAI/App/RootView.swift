import OSLog
import SwiftData
import SwiftUI

/// Root navigation (ARCHITECTURE §2.2): one `NavigationStack` bound to `Router.path`.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    /// The iPhone's own Dynamic Type size (read above our override, D-318 "Theo iPhone").
    @Environment(\.dynamicTypeSize) private var systemTextSize
    @Environment(\.appEnv) private var env
    @Environment(HandoffPromptCoordinator.self) private var handoff
    @Environment(\.scenePhase) private var scenePhase
    @State private var toast: ToastModel?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            rootScreen
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        // D-318: whole app, sheets included. Always the same modifier (no if/else), so changing the size never
        // rebuilds the navigation stack (the user stays on the Settings page).
        .dynamicTypeSize(AppTextSize(stored: env.localData.settings().textSize).dynamicTypeSize ?? systemTextSize)
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
            // ARCHITECTURE §6.5: Transaction.updates from launch (renewals, Ask to Buy, refunds) → backend → plan.
            for await jws in env.purchases.transactionUpdates {
                if let me = await BillingSync.verify(jws, api: env.api, purchases: env.purchases) { appState.apply(me: me) }
            }
        }
        .task {
            for await screen in env.api.blockingUpdates {
                appState.blockingScreen = screen
            }
        }
        .fullScreenCover(isPresented: isBlocked) { blockingCover }
        // S08 (D-242): asked once per hand-off, only when signed in (the prompt sits over any screen).
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background: handoff.didEnterBackground()
            case .active:
                if case .signedIn = appState.session { handoff.didBecomeActive() }
                // D-316: wake the hosted backend while the user is still speaking (free hosts may sleep).
                Task { _ = try? await env.api.health() }
            default: break
            }
        }
        .onChange(of: appState.session) { _, session in
            if case .signedIn = session, scenePhase == .active { handoff.didBecomeActive() }
        }
        .sheet(item: handoffPrompt) { prompt in
            HandoffPromptSheet(prompt: prompt, onDone: handoff.answerDone, onNotYet: handoff.answerNotYet)
                .onAppear(perform: handoff.didShow)
        }
        .onChange(of: handoff.toast) { _, message in
            guard let message else { return }
            toast = ToastModel(message: message)
            handoff.toast = nil
        }
        .toast($toast)
        .task(id: appState.session) {
            await loadAccount()
        }
        // D-170: Siri / Action Button / Back Tap / widget → S03 listening, once signed in (the flag waits for it).
        .onChange(of: appState.startListeningRequested, initial: true) { _, _ in openListeningIfRequested() }
        .onChange(of: appState.session) { _, _ in openListeningIfRequested() }
    }

    private func openListeningIfRequested() {
        guard appState.startListeningRequested, case .signedIn = appState.session, appState.blockingScreen == nil
        else { return }
        appState.startListeningRequested = false
        router.popToRoot()
        router.push(.conversation(nil))                                    // a new request, mic on (S03 mode 1)
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

    private var handoffPrompt: Binding<HandoffPrompt?> {
        Binding(get: { handoff.prompt }, set: { if $0 == nil { handoff.dismissed() } })
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
                                                       permissions: env.permissions, contacts: env.contacts,
                                                       calendar: env.calendar, localData: env.localData,
                                                       system: env.system, tts: env.tts, images: env.images,
                                                       snoozeMorningHour: env.localData.settings().snoozeMorningHour,
                                                       speech: env.speech))
        case .conversation(let draftId):
            ConversationView(viewModel: ConversationViewModel(draftId: draftId, repository: env.drafts, speech: env.speech, api: env.api,
                                                              tts: env.tts, localData: env.localData,
                                                              permissions: env.permissions, engine: env.engine))
        case .mailReply(let reply):
            ConversationView(viewModel: ConversationViewModel(draftId: nil, repository: env.drafts, speech: env.speech, api: env.api,
                                                              tts: env.tts, localData: env.localData,
                                                              permissions: env.permissions, engine: env.engine, reply: reply))
        case .calendarToday:
            CalendarTodayView(viewModel: CalendarTodayViewModel(calendar: env.calendar, permissions: env.permissions,
                                                                repository: env.drafts, engine: env.engine))
        case .calendarDay(let day):
            CalendarTodayView(viewModel: CalendarTodayViewModel(calendar: env.calendar, permissions: env.permissions,
                                                                repository: env.drafts, engine: env.engine,
                                                                day: day))
        case .mail(let codesOnly):
            MailView(viewModel: MailViewModel(gmail: env.gmail, api: env.api, tts: env.tts, system: env.system,
                                              codesOnly: codesOnly,
                                              speechRate: env.localData.settings().speechRate))
        case .reminders:
            RemindersView(viewModel: RemindersViewModel(reminders: env.reminders, permissions: env.permissions,
                                                        repository: env.drafts, engine: env.engine,
                                                        snoozeMorningHour: env.localData.settings().snoozeMorningHour))
        case .places:
            PlacesView(viewModel: PlacesViewModel(places: env.places, localData: env.localData, engine: env.engine))
        case .ocr:
            OCRCaptureView(viewModel: OCRCaptureViewModel(permissions: env.permissions,
                                                          cameraAvailable: CameraPicker.isAvailable,
                                                          repository: env.drafts, images: env.images,
                                                          photoLibrary: env.photoLibrary, localData: env.localData,
                                                          ocr: env.ocr, api: env.api, engine: env.engine))
        case .history:
            HistoryView(viewModel: HistoryViewModel(repository: env.drafts))
        case .settings:
            SettingsView(viewModel: SettingsViewModel(localData: env.localData, drafts: env.drafts, auth: env.auth,
                                                      tts: env.tts, permissions: env.permissions,
                                                      contacts: env.contacts, photoLibrary: env.photoLibrary,
                                                      gmail: env.gmail, gmailAvailable: env.config.gmailClientID != nil,
                                                      api: env.api, images: env.images))
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
        .environment(HandoffPromptCoordinator(repository: MockTaskRepository(), engine: AppEnvironment.mock().engine))
        .modelContainer(try! ModelContainerFactory.make(inMemory: true))   // preview only
}
