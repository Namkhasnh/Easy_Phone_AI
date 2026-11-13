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
                                       engine: TaskEngine(repository: repo, now: { Self.now }),
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

    // MARK: - D-294 other days

    @Test func dayFromVoiceShowsTomorrowAndArrowsMove() async {
        let perms = MockPermissionManager([.calendar: .granted])
        let vm = CalendarTodayViewModel(calendar: MockCalendarService([Self.event("a", "Khám răng", 9, 10),
                                                                       Self.event("t", "Nha sĩ", 33, 34)]),
                                        permissions: perms, repository: repo,
                                        engine: TaskEngine(repository: repo, now: { Self.now }),
                                        now: { Self.now }, timeZone: Self.tz, day: "2026-11-14")
        await vm.load()
        #expect(vm.titleKey == "calendar.title.tomorrow")
        #expect(vm.rows.map(\.id) == ["t"])
        #expect(vm.rows.first?.time == "09:00")
        await vm.move(by: -1)
        #expect(vm.titleKey == "calendar.title" && vm.rows.map(\.id) == ["a"])
        await vm.move(by: -1)
        #expect(vm.titleKey == "calendar.title.yesterday" && vm.isEmpty && vm.emptyKey == "calendar.empty.day")
        await vm.move(by: 5)
        #expect(vm.titleKey == "calendar.title.other")
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

/// 1C.4b — S11 detail sheet, "Sửa" / "Xóa" → S04 (UI_SCREENS S11, spec §6.4 AC3–AC5, D-100, D-108).
@MainActor
@Suite("S11 detail → S04")
struct CalendarTodayDetailTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-13T08:00:00+07:00")!
    static func at(_ h: Double) -> Date { Validator.parseDateTime("2026-11-13T00:00:00+07:00")! + h * 3600 }

    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()
    let calendar: MockCalendarService
    let engine: TaskEngine

    init() {
        calendar = MockCalendarService([
            EventSummary(id: "ev-1", title: "Khám răng", start: Self.at(14), end: Self.at(15), isAllDay: false,
                         location: "Nha khoa Hoa Sen", alertMinutesBefore: 60, calendarId: "cal-1", calendarName: "Nhà",
                         isRecurring: false),
            EventSummary(id: "ev-r", title: "Tập dưỡng sinh", start: Self.at(6), end: Self.at(7), isAllDay: false,
                         isRecurring: true),
        ])
        engine = TaskEngine(repository: repo,
                            executors: [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions)],
                            now: { Self.now })
    }

    func model() async -> CalendarTodayViewModel {
        let vm = CalendarTodayViewModel(calendar: calendar, permissions: permissions, repository: repo, engine: engine,
                                        now: { Self.now }, timeZone: Self.tz)
        await vm.load()
        return vm
    }

    @Test func detailShowsReadOnlyFieldsWithoutLockedIds() async {
        let vm = await model()
        vm.select("ev-1")
        let rows = vm.detailRows
        #expect(rows.map(\.labelKey) == ["field.calendarEvent.title", "field.calendarEvent.startDate",
                                         "field.calendarEvent.endDate", "field.calendarEvent.location",
                                         "field.calendarEvent.alertMinutesBefore"])          // no calendarId 🔒, no allDay=false
        #expect(rows[0].value == "Khám răng")
        #expect(rows[1].value == "Thứ Sáu, 13/11 lúc 14:00")
        #expect(vm.canChangeSelected)
        #expect(vm.openInCalendarURL?.scheme == "calshow")
    }

    @Test func editOpensAnUpdateDraftAndChangesNothingYet() async throws {
        let vm = await model()
        vm.select("ev-1")
        vm.change(.update)
        #expect(vm.selected == nil)
        let draft = try #require(vm.reviewDraftId.flatMap(repo.draft))
        let step = draft.steps[0]
        #expect(step.kind == .calendarEvent && step.operation == .update && step.targetRef == "ev-1")
        #expect(step.state == .awaitingApproval)
        #expect(step.field("calendarId")?.value == "cal-1" && step.field("title")?.source == .device(origin: "calendar"))
        #expect(calendar.saveCount == 0)                                     // D-100: nothing before "Xác nhận"
    }

    @Test func deleteGoesThroughReviewThenRemovesTheEvent() async throws {
        let vm = await model()
        vm.select("ev-1")
        vm.change(.delete)
        let draft = try #require(vm.reviewDraftId.flatMap(repo.draft))
        let review = ReviewViewModel(draftId: draft.id, repository: repo, engine: engine, permissions: permissions)
        #expect(review.isDelete && review.blocker == nil)                    // "Xác nhận xóa", tap only (D-108)
        #expect(calendar.deleted.isEmpty)
        await review.confirm()
        #expect(review.step?.state == .succeeded)
        #expect(review.step?.resultEvidence == "ek:deleted:ev-1")
        #expect(calendar.deleted == ["ev-1"])
        await vm.load()
        #expect(vm.rows.map(\.id) == ["ev-r"])
    }

    @Test func recurringCannotBeChanged() async {
        let vm = await model()
        vm.select("ev-r")
        #expect(!vm.canChangeSelected)
        vm.change(.delete)
        #expect(vm.reviewDraftId == nil && vm.selected != nil)               // spec §6.4 AC5
        #expect(engine.startDraft(from: calendar.all.first { $0.isRecurring }!, operation: .update) == nil)
    }
}
