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
    /// EventKit reminders: list, save with `easyphone:<stepId>`, complete, snooze (1C.5, D-225, D-248).
    let reminders: any RemindersService
    /// Device contacts: Vietnamese name / nickname matching, phone numbers (1C.7, DATA_MODEL §7.2).
    let contacts: any ContactsService

    @MainActor static func live(container: ModelContainer) -> AppEnvironment {
        let config = AppConfig.fromMainBundle()
        let auth = LiveAuthService(config: config)
        let drafts = LiveTaskRepository(container: container)
        let permissions = LivePermissionManager()
        let calendar = LiveCalendarService()
        let reminders = LiveRemindersService()
        let localData = LiveLocalDataRepository(container: container)
        let contacts = LiveContactsService { localData.nickname(matching: $0)?.contactId }
        return AppEnvironment(config: config, auth: auth,
                              api: APIClient(config: config, auth: auth, client: .fromMainBundle()),
                              drafts: drafts,
                              localData: localData,
                              engine: TaskEngine(repository: drafts,
                                                 executors: executors(calendar, reminders, permissions, localData),
                                                 resolver: DeviceResolver(contacts: contacts, calendar: calendar,
                                                                          permissions: permissions)),
                              speech: LiveSpeechService(), tts: LiveTTSService(),
                              permissions: permissions, calendar: calendar, reminders: reminders, contacts: contacts)
    }

    static func mock(_ scenario: MockScenario = .default) -> AppEnvironment {
        let drafts = MockTaskRepository()
        let permissions = MockPermissionManager()
        let calendar = MockCalendarService()
        let reminders = MockRemindersService()
        let localData = MockLocalDataRepository()
        let contacts = MockContactsService()
        return AppEnvironment(config: .mock, auth: MockAuthService(), api: MockAPIClient(), drafts: drafts,
                              localData: localData,
                              engine: TaskEngine(repository: drafts,
                                                 executors: executors(calendar, reminders, permissions, localData),
                                                 resolver: DeviceResolver(contacts: contacts, calendar: calendar,
                                                                          permissions: permissions)),
                              speech: MockSpeechService(), tts: MockTTSService(),
                              permissions: permissions, calendar: calendar, reminders: reminders, contacts: contacts)
    }

    /// One executor per kind (ARCHITECTURE §5.1); the others are added by their items (1C.5, 1C.10 – 1C.13, 1D).
    private static func executors(_ calendar: any CalendarService, _ reminders: any RemindersService,
                                  _ permissions: any PermissionManager,
                                  _ localData: any LocalDataRepository) -> [TaskKind: any StepExecutor] {
        [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions),
         .reminder: RemindersExecutor(reminders: reminders, permissions: permissions,
                                      morningHour: { localData.settings().snoozeMorningHour })]
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
