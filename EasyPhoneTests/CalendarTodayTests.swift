import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.4a — UI_SCREENS S11, spec §6.4 AC1 / AC2, D-185.
@MainActor
@Suite("S11 Calendar today")
struct CalendarTodayTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-13T08:00:00+07:00")!       // Thứ Sáu
    static func at(_ h: Double) -> Date { Validator.parseDateTime("2026-11-13T00:00:00+07:00")! + h * 3600 }
    static func event(_ id: String, _ title: String, _ s: Double, _ e: Double, allDay: Bool = false,
                      location: String? = nil) -> EventSummary {
        EventSummary(id: id, title: title, start: at(s), end: at(e), isAllDay: allDay, location: location, isRecurring: false)
    }

    let repo = MockTaskRepository()

    func model(_ events: [EventSummary], access: PermissionStatus = .granted,
               answer: PermissionStatus = .granted) -> (CalendarTodayViewModel, MockPermissionManager) {
        let perms = MockPermissionManager([.calendar: access], answer: answer)
        return (CalendarTodayViewModel(calendar: MockCalendarService(events), permissions: perms, repository: repo,
                                       now: { Self.now }, timeZone: Self.tz), perms)
    }

    @Test func listsTodayInOrderWithConflictsAndAllDay() async {
        let (vm, _) = model([Self.event("b", "Họp tổ", 9.5, 11), Self.event("a", "Khám răng", 9, 10, location: "Hoa Sen"),
                             Self.event("c", "Sinh nhật mẹ", 0, 24, allDay: true), Self.event("d", "Đón cháu", 16.5, 17),
                             Self.event("x", "Ngày mai", 33, 34)])
        await vm.load()
        #expect(vm.rows.map(\.id) == ["c", "a", "b", "d"])                         // today only, by start
        #expect(vm.rows.map(\.time) == ["Cả ngày", "09:00", "09:30", "16:30"])
        #expect(vm.rows.filter(\.conflicts).map(\.id) == ["a", "b"])               // all-day never conflicts
        #expect(vm.rows[1].location == "Hoa Sen")
        #expect(vm.dayText == "Thứ Sáu, 13/11")
        #expect(!vm.isEmpty)
    }

    @Test func emptyDayShowsEmptyState() async {
        let (vm, _) = model([])
        #expect(!vm.isEmpty)                                                        // not before loading
        await vm.load()
        #expect(vm.isEmpty)
    }

    @Test func notDeterminedAsksAfterExplainerThenLoads() async {
        let (vm, perms) = model([Self.event("a", "Khám răng", 9, 10)], access: .notDetermined)
        await vm.load()
        #expect(vm.pendingPermission == PendingPermission(capability: .calendar, variant: .explainer))
        #expect(perms.requested.isEmpty && vm.rows.isEmpty)                        // D-185
        await vm.allowPermission()
        #expect(perms.requested == [.calendar])
        #expect(vm.rows.map(\.id) == ["a"])
    }

    @Test(arguments: [PermissionStatus.denied, .restricted, .writeOnly])
    func cannotReadShowsDenied(_ status: PermissionStatus) async {
        let (vm, perms) = model([Self.event("a", "Khám răng", 9, 10)], access: status)
        await vm.load()
        #expect(vm.pendingPermission?.variant == .denied)
        #expect(vm.rows.isEmpty && perms.requested.isEmpty)
    }

    @Test func addEventOpensAnEmptyTypedDraft() async throws {
        let (vm, _) = model([])
        vm.addEvent()
        let id = try #require(vm.newDraftId)
        let draft = try #require(repo.draft(id))
        #expect(draft.inputMode == .text && draft.originalInput.isEmpty && draft.steps.isEmpty)
        // S03 opens it as an editable transcript: no listening, no auto-send.
        let conv = ConversationViewModel(draftId: id, repository: repo, speech: MockSpeechService(), api: MockAPIClient(),
                                         tts: MockTTSService(), localData: MockLocalDataRepository())
        await conv.onAppear()
        #expect(conv.mode == .transcript && conv.text.isEmpty)
    }

    @Test func s11StringsExist() {
        for key in ["calendar.title", "calendar.empty", "calendar.add", "calendar.allDay", "calendar.conflict",
                    "calendar.delete", "calendar.recurringUnsupported", "calendar.limitedNote"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
    }
}
