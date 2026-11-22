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
    /// Gmail connection (Phase 2, API_GMAIL §2–§3).
    let gmail: any GmailService
    /// StoreKit 2 (Phase 1F, ARCHITECTURE §6.5).
    let purchases: any PurchaseService

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
        let gmail = LiveGmailService(api: api, clientID: config.gmailClientID)
        return AppEnvironment(config: config, auth: auth,
                              api: api,
                              drafts: drafts,
                              localData: localData,
                              engine: TaskEngine(repository: drafts,
                                                 executors: executors(calendar, reminders, permissions, localData,
                                                                      calls: LiveCallService(), messages: LiveMessagesService(),
                                                                      system: system, places: places,
                                                                      api: api, gmail: gmail),
                                                 serviceIds: SupportedServices.bundled.ids,
                                                 resolver: DeviceResolver(contacts: contacts, calendar: calendar,
                                                                          permissions: permissions, places: places,
                                                                          savedPlaces: { localData.savedPlaces() })),
                              speech: LiveSpeechService(),
                              tts: LiveTTSService(preferences: {                       // D-324
                                  let s = localData.settings()
                                  return TTSPreferences(voiceId: s.ttsVoiceId, pitch: s.ttsPitch)
                              }),
                              permissions: permissions, calendar: calendar, reminders: reminders, contacts: contacts,
                              system: system, places: places,
                              images: LiveImageStore(), photoLibrary: LivePhotoLibraryService(),
                              ocr: RoutingOCRService(device: VisionOCRService(), remote: APIRemoteOCR(api: api)),
                              gmail: gmail, purchases: LivePurchaseService())
    }

    /// `options` / `drafts`: 1G.10 resilience UI tests only (on-disk drafts, offline backend, denied permissions).
    static func mock(_ scenario: MockScenario = .default, options: MockScenario.UITestOptions = .init(),
                     drafts storedDrafts: (any TaskRepository)? = nil) -> AppEnvironment {
        let drafts: any TaskRepository = storedDrafts ?? MockTaskRepository()
        let denied: Set<Capability> = options.denied ? [.calendar, .reminders, .contacts] : []
        let permissions = scenario == .uiTest
            ? MockPermissionManager(Dictionary(uniqueKeysWithValues: Capability.allCases.map {
                ($0, denied.contains($0) ? PermissionStatus.denied : .granted)
            }))
            : MockPermissionManager()
        let calendar = MockCalendarService()
        let reminders = MockRemindersService()
        let localData = MockLocalDataRepository()
        let contacts = scenario == .uiTest ? MockContactsService.uiTest : MockContactsService()
        let system = MockSystemService()
        let places = MockPlacesService()
        let auth = scenario == .uiTest ? MockAuthService(initial: .signedIn(userId: MockAuthService.userId)) : MockAuthService()
        let api = scenario != .uiTest ? MockAPIClient()
            : options.offline ? MockAPIClient(parse: .failure(.network(.offline)))
            : MockAPIClient(parseRouter: uiTestParse, extract: .success(uiTestExtract()))
        let gmail = MockGmailService(accounts: scenario == .uiTest ? [MockGmailService.sample] : [])
        return AppEnvironment(config: .mock, auth: auth, api: api, drafts: drafts,
                              localData: localData,
                              engine: TaskEngine(repository: drafts,
                                                 executors: executors(calendar, reminders, permissions, localData,
                                                                      calls: MockCallService(),
                                                                      // Simulator cannot send SMS; the system composer
                                                                      // cannot be driven by XCUITest either (1C.18b).
                                                                      messages: MockMessagesService(canSendText: scenario != .uiTest),
                                                                      system: system, places: places,
                                                                      api: api, gmail: gmail),
                                                 serviceIds: SupportedServices.bundled.ids,
                                                 resolver: DeviceResolver(contacts: contacts, calendar: calendar,
                                                                          permissions: permissions, places: places,
                                                                          savedPlaces: { localData.savedPlaces() })),
                              speech: MockSpeechService(), tts: MockTTSService(),
                              permissions: permissions, calendar: calendar, reminders: reminders, contacts: contacts,
                              system: system, places: places,
                              images: MockImageStore(), photoLibrary: MockPhotoLibraryService(),
                              ocr: MockOCRService(), gmail: gmail, purchases: MockPurchaseService())
    }

    /// `MockScenario.uiTest` `/v1/extract` (flow 1, 1D.11): `ExtractResponse.mock` with the date moved to tomorrow
    /// 09:30, so the linked event / reminder is not "in the past" whenever the test runs.
    private static func uiTestExtract(now: Date = .now) -> ExtractResponse {
        let tz = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let date = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        let value = ParseRequest.nowString(date, in: tz)
        let mock = ExtractResponse.mock
        return ExtractResponse(schemaVersion: mock.schemaVersion, requestId: mock.requestId,
                               fields: mock.fields.map { field in
                                   guard field.id == "dateTime" else { return field }
                                   return .init(id: field.id, value: value, confidence: field.confidence, span: field.span)
                               },
                               suggestedNextAction: mock.suggestedNextAction)
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

    /// One executor per kind (ARCHITECTURE §5.1); ride / food wait for Phase 3.
    private static func executors(_ calendar: any CalendarService, _ reminders: any RemindersService,
                                  _ permissions: any PermissionManager,
                                  _ localData: any LocalDataRepository,
                                  calls: any CallService,
                                  messages: any MessagesService,
                                  system: any SystemService,
                                  places: any PlacesService,
                                  api: any APIClientProtocol,
                                  gmail: any GmailService) -> [TaskKind: any StepExecutor] {
        [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions),
         .call: CallExecutor(calls: calls),
         .sms: SMSExecutor(messages: messages, system: system),
         .place: PlaceExecutor(places: places, localData: localData),
         .reminder: RemindersExecutor(reminders: reminders, permissions: permissions,
                                      morningHour: { localData.settings().snoozeMorningHour }),
         .ocr: OCRExecutor(system: system),
         .emailReply: EmailDraftExecutor(api: api, gmail: gmail)]
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

    /// 1G.10 resilience UI tests: `-uiTestDisk YES` (drafts in an on-disk test store that survives a relaunch),
    /// `-uiTestResetStore YES` (start it empty), `-uiTestOffline YES` (`/v1/parse` fails offline),
    /// `-uiTestDenied YES` (calendar / reminders / contacts denied). Only read together with `-uiTestScenario`.
    struct UITestOptions: Sendable, Hashable {
        var disk = false, resetStore = false, offline = false, denied = false

        static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> UITestOptions {
            UITestOptions(disk: defaults.bool(forKey: "uiTestDisk"), resetStore: defaults.bool(forKey: "uiTestResetStore"),
                          offline: defaults.bool(forKey: "uiTestOffline"), denied: defaults.bool(forKey: "uiTestDenied"))
        }
    }
}

extension EnvironmentValues {
    /// The app root always injects `.live()`; previews inject `.mock(...)`. The default is a mock so a
    /// forgotten injection in a preview never touches real device data.
    @Entry var appEnv: AppEnvironment = .mock()
}
