import SwiftData
import SwiftUI

/// Dependency container (ARCHITECTURE §3). Built once in `EasyPhoneApp`, injected via `.environment(\.appEnv, …)`.
/// Service properties are added by the item that builds each service (protocol + Live + Mock, D-206):
/// device services (1C),
/// `ocr` (1D), `purchases` (1F). Debug vs Release never changes the wiring (D-208).
struct AppEnvironment: Sendable {
    /// Build configuration from `Config/*.xcconfig` (0.7, D-207).
    let config: AppConfig
    /// Google sign-in + session (0.9, D-283).
    let auth: any AuthService
    /// Backend `/v1/*` (0.16, API_CONTRACT §10).
    let api: any APIClientProtocol
    /// `TaskDraft` persistence, SwiftData main context (1A.9, ARCHITECTURE §4.4).
    let drafts: any TaskRepository
    /// Saved places, nicknames, settings (1A.9b, DATA_MODEL §5).
    let localData: any LocalDataRepository
    /// The only writer of task steps (ARCHITECTURE §5); executors are added per kind in 1C / 1D.
    let engine: TaskEngine
    /// Speech-to-text, vi-VN on device (1B.2, ARCHITECTURE §4.3).
    let speech: any SpeechService
    /// Text-to-speech, vi-VN on device (1B.3, ARCHITECTURE §4.3).
    let tts: any TTSService
    /// Status + request for the 8 capabilities; asked only after the S18 explainer (1C.1, D-185).
    let permissions: any PermissionManager
    /// EventKit events: conflicts, search, save with `easyphone:<stepId>` (1C.2, D-225).
    let calendar: any CalendarService

    @MainActor static func live(container: ModelContainer) -> AppEnvironment {
        let config = AppConfig.fromMainBundle()
        let auth = LiveAuthService(config: config)
        let drafts = LiveTaskRepository(container: container)
        let permissions = LivePermissionManager()
        let calendar = LiveCalendarService()
        return AppEnvironment(config: config, auth: auth,
                              api: APIClient(config: config, auth: auth, client: .fromMainBundle()),
                              drafts: drafts,
                              localData: LiveLocalDataRepository(container: container),
                              engine: TaskEngine(repository: drafts, executors: executors(calendar, permissions)),
                              speech: LiveSpeechService(), tts: LiveTTSService(),
                              permissions: permissions, calendar: calendar)
    }

    static func mock(_ scenario: MockScenario = .default) -> AppEnvironment {
        let drafts = MockTaskRepository()
        let permissions = MockPermissionManager()
        let calendar = MockCalendarService()
        return AppEnvironment(config: .mock, auth: MockAuthService(), api: MockAPIClient(), drafts: drafts,
                              localData: MockLocalDataRepository(),
                              engine: TaskEngine(repository: drafts, executors: executors(calendar, permissions)),
                              speech: MockSpeechService(), tts: MockTTSService(),
                              permissions: permissions, calendar: calendar)
    }

    /// One executor per kind (ARCHITECTURE §5.1); the others are added by their items (1C.5, 1C.10 – 1C.13, 1D).
    private static func executors(_ calendar: any CalendarService,
                                  _ permissions: any PermissionManager) -> [TaskKind: any StepExecutor] {
        [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions)]
    }
}

/// Mock scenarios for previews and tests (ARCHITECTURE §13).
/// Cases `offline`, `quotaExceeded`, `permissionDenied`, `threeMinh`, `uiTest` are added with the mocks that need them.
enum MockScenario: Sendable, Hashable {
    case `default`
}

extension EnvironmentValues {
    /// The app root always injects `.live()`; previews inject `.mock(...)`. The default is a mock so a
    /// forgotten injection in a preview never touches real device data.
    @Entry var appEnv: AppEnvironment = .mock()
}
