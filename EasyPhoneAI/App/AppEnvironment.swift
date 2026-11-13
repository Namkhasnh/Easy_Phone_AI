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
    /// Open other apps / clipboard (ARCHITECTURE §4.2, D-293).
    let system: any SystemService
    /// MapKit search + directions hand-off (1C.13, spec §6.9).
    let places: any PlacesService
    /// OCR photos in `Application Support/ocr/` (1D.2, ARCHITECTURE §6.4).
    let images: any ImageStore
    /// Optional copy of camera photos in the Photos library (D-301).
    let photoLibrary: any PhotoLibraryService
    /// Text from the photo: Vision first, `/v1/ocr` fallback (1D.3, ARCHITECTURE §4.3, D-061).
    let ocr: any OCRService

    @MainActor static func live(container: ModelContainer) -> AppEnvironment {
        let config = AppConfig.fromMainBundle()
        let auth = LiveAuthService(config: config)
        let drafts = LiveTaskRepository(container: container)
        let permissions = LivePermissionManager()
        let calendar = LiveCalendarService()
        let reminders = LiveRemindersService()
        let localData = LiveLocalDataRepository(container: container)
        let contacts = LiveContactsService { localData.nickname(matching: $0)?.contactId }
        let system = LiveSystemService()
        let places = LivePlacesService(system: system)
        let api = APIClient(config: config, auth: auth, client: .fromMainBundle())
        return AppEnvironment(config: config, auth: auth,
                              api: api,
                              drafts: drafts,
                              localData: localData,
                              engine: TaskEngine(repository: drafts,
                                                 executors: executors(calendar, reminders, permissions, localData,
                                                                      calls: LiveCallService(), messages: LiveMessagesService(),
                                                                      system: system, places: places),
                                                 serviceIds: SupportedServices.bundled.ids,
                                                 resolver: DeviceResolver(contacts: contacts, calendar: calendar,
                                                                          permissions: permissions, places: places,
                                                                          savedPlaces: { localData.savedPlaces() })),
                              speech: LiveSpeechService(), tts: LiveTTSService(),
                              permissions: permissions, calendar: calendar, reminders: reminders, contacts: contacts,
                              system: system, places: places,
                              images: LiveImageStore(), photoLibrary: LivePhotoLibraryService(),
                              ocr: RoutingOCRService(device: VisionOCRService(), remote: APIRemoteOCR(api: api)))
    }

    static func mock(_ scenario: MockScenario = .default) -> AppEnvironment {
        let drafts = MockTaskRepository()
        let permissions = scenario == .uiTest
            ? MockPermissionManager(Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, .granted) }))
            : MockPermissionManager()
        let calendar = MockCalendarService()
        let reminders = MockRemindersService()
        let localData = MockLocalDataRepository()
        let contacts = scenario == .uiTest ? MockContactsService.uiTest : MockContactsService()
        let system = MockSystemService()
        let places = MockPlacesService()
        let auth = scenario == .uiTest ? MockAuthService(initial: .signedIn(userId: MockAuthService.userId)) : MockAuthService()
        let api = scenario == .uiTest ? MockAPIClient(parseRouter: uiTestParse) : MockAPIClient()
        return AppEnvironment(config: .mock, auth: auth, api: api, drafts: drafts,
                              localData: localData,
                              engine: TaskEngine(repository: drafts,
                                                 executors: executors(calendar, reminders, permissions, localData,
                                                                      calls: MockCallService(),
                                                                      // Simulator cannot send SMS; the system composer
                                                                      // cannot be driven by XCUITest either (1C.18b).
                                                                      messages: MockMessagesService(canSendText: scenario != .uiTest),
                                                                      system: system, places: places),
                                                 serviceIds: SupportedServices.bundled.ids,
                                                 resolver: DeviceResolver(contacts: contacts, calendar: calendar,
                                                                          permissions: permissions, places: places,
                                                                          savedPlaces: { localData.savedPlaces() })),
                              speech: MockSpeechService(), tts: MockTTSService(),
                              permissions: permissions, calendar: calendar, reminders: reminders, contacts: contacts,
                              system: system, places: places,
                              images: MockImageStore(), photoLibrary: MockPhotoLibraryService(),
                              ocr: MockOCRService())
    }

    /// `MockScenario.uiTest` `/v1/parse`: a request starting with "Gọi" → call anh Minh, anything else → `mockSMS`.
    private static let uiTestParse: @Sendable (ParseRequest) -> ParsedDraft? = { request in
        guard request.text.lowercased().hasPrefix("gọi") else { return .mockSMS }
        return ParsedDraft(schemaVersion: 1, requestId: "req_uitest_call",
                           steps: [ParsedStep(kind: "call", operation: "open", fields: [
                               ParsedField(id: "recipientName", value: "anh Minh", confidence: 0.95, sourceQuote: "anh Minh"),
                           ], dateCandidates: [])],
                           followUpQuestion: nil, unsupported: nil)
    }

    /// One executor per kind (ARCHITECTURE §5.1); the others are added by their items (1C.5, 1C.10 – 1C.13, 1D).
    private static func executors(_ calendar: any CalendarService, _ reminders: any RemindersService,
                                  _ permissions: any PermissionManager,
                                  _ localData: any LocalDataRepository,
                                  calls: any CallService,
                                  messages: any MessagesService,
                                  system: any SystemService,
                                  places: any PlacesService) -> [TaskKind: any StepExecutor] {
        [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions),
         .call: CallExecutor(calls: calls),
         .sms: SMSExecutor(messages: messages, system: system),
         .place: PlaceExecutor(places: places, localData: localData),
         .reminder: RemindersExecutor(reminders: reminders, permissions: permissions,
                                      morningHour: { localData.settings().snoozeMorningHour })]
    }
}

/// Mock scenarios for previews and tests (ARCHITECTURE §13).
/// Cases `offline`, `quotaExceeded`, `permissionDenied`, `threeMinh` are added with the mocks that need them.
enum MockScenario: String, Sendable, Hashable {
    case `default`
    /// XCUITest (1C.18): signed in, every permission granted, contact "Nguyễn Văn Minh" with one mobile number,
    /// `/v1/parse` answers `ParsedDraft.mockSMS`. Selected by the launch argument `-uiTestScenario uiTest`.
    case uiTest

    /// `-uiTestScenario <name>` (ARCHITECTURE §13). Launch arguments cannot be set by a user on a device, so
    /// this never changes the wiring of a normal launch (D-208).
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> MockScenario? {
        defaults.string(forKey: "uiTestScenario").flatMap(MockScenario.init(rawValue:))
    }
}

extension EnvironmentValues {
    /// The app root always injects `.live()`; previews inject `.mock(...)`. The default is a mock so a
    /// forgotten injection in a preview never touches real device data.
    @Entry var appEnv: AppEnvironment = .mock()
}
