import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.9a — ARCHITECTURE §5 DeviceResolver, DATA_MODEL §6.2 / §7.2, D-106, D-247, D-253, AI_PROMPTS E7.
@MainActor
@Suite("DeviceResolver")
struct DeviceResolverTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    static let people: [ContactRecord] = [
        ContactRecord(id: "minh1", givenName: "Minh", middleName: "Văn", familyName: "Nguyễn", phoneCount: 2),
        ContactRecord(id: "minh2", givenName: "Mính", familyName: "Trần", phoneCount: 1),
        ContactRecord(id: "lan", givenName: "Lan", familyName: "Nguyễn", phoneCount: 1),
    ]
    static let phones: [String: [PhoneEntry]] = [
        "minh1": [PhoneEntry(label: "di động", number: "0901 234 567"), PhoneEntry(label: "nhà", number: "0912 000 111")],
        "minh2": [PhoneEntry(label: nil, number: "+84 98 765 4321")],
        "lan": [PhoneEntry(label: "di động", number: "0903.333.444")],
    ]

    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()
    let calendar = MockCalendarService()
    let contacts = MockContactsService(people, phones: phones, nicknames: ["mẹ": "lan"])
    var engine: TaskEngine {
        TaskEngine(repository: repo, resolver: DeviceResolver(contacts: contacts, calendar: calendar, permissions: permissions),
                   now: { Self.now })
    }

    func draft(_ kind: TaskKind, _ op: TaskOperation, _ values: [String: String]) -> TaskDraft {
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: 0.9, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh",
                          steps: [TaskStep(order: 0, kind: kind, operation: op, fields: fields)])
        repo.save(d)
        return d
    }

    func resolved(_ d: TaskDraft) async -> TaskStep {
        let e = engine
        e.revalidate(stepId: d.steps[0].id, in: d)
        await e.resolveDevice(in: d)
        return d.steps[0]
    }

    @Test func nicknameOneContactOneNumberIsFilledAndConfirmable() async {
        let step = await resolved(draft(.call, .open, ["recipientName": "mẹ"]))
        #expect(step.field("contactId")?.value == "lan")
        #expect(step.field("phoneNumber")?.value == "+84903333444")
        #expect(step.field("contactId")?.source == .device(origin: "contacts"))
        #expect(step.field("recipientName")?.value == "mẹ")                  // original kept (§7.2)
        #expect(step.state == .awaitingApproval)
    }

    @Test func severalContactsMakeAContactAmbiguityNeverAutoPicked() async throws {
        let step = await resolved(draft(.sms, .open, ["recipientName": "anh Minh", "body": "Em đến muộn", "channel": "sms"]))
        #expect(step.field("contactId")?.value == nil)                      // D-106
        let amb = try #require(step.field("contactId")?.ambiguity)
        #expect(amb.kind == .contact && amb.question == "Bạn muốn nhắn anh Minh nào?")
        #expect(Set(amb.candidates.map(\.id)) == ["minh1", "minh2"])
        #expect(amb.candidates.first { $0.id == "minh2" }?.subtitle == "•••• 321")   // 1 number → masked
        #expect(amb.candidates.first { $0.id == "minh1" }?.subtitle == nil)          // 2 numbers → chosen later
        #expect(step.state == .needsInfo || step.state == .draft)
    }

    @Test func oneContactSeveralNumbersMakeAPhoneAmbiguity() async throws {
        let step = await resolved(draft(.call, .open, ["recipientName": "Nguyễn Văn Minh"]))
        #expect(step.field("contactId")?.value == "minh1")
        let amb = try #require(step.field("phoneNumber")?.ambiguity)
        #expect(amb.kind == .phoneNumber && amb.question == "Bạn muốn dùng số nào của Nguyễn Văn Minh?")
        #expect(amb.candidates.map(\.id) == ["+84901234567", "+84912000111"])
        #expect(amb.candidates.map(\.title) == ["di động: •••• 567", "nhà: •••• 111"])
    }

    @Test func noMatchIsAnEmptyContactAmbiguity() async throws {
        let step = await resolved(draft(.call, .open, ["recipientName": "Hùng"]))
        let amb = try #require(step.field("contactId")?.ambiguity)
        #expect(amb.candidates.isEmpty && amb.question == "Mình chưa tìm thấy người này, bạn chọn trong danh bạ nhé")
    }

    @Test func spokenNumberSkipsContacts() async {                          // D-253
        let step = await resolved(draft(.call, .open, ["recipientName": "0901 234 567"]))
        #expect(step.field("phoneNumber")?.value == "+84901234567")
        #expect(step.field("contactId")?.value == nil && step.field("contactId")?.ambiguity == nil)
        #expect(step.state == .awaitingApproval)
    }

    @Test func copyOnlyChannelSkipsContacts() async {                       // D-247
        let step = await resolved(draft(.sms, .open, ["recipientName": "mẹ", "body": "Con về muộn", "channel": "viber"]))
        #expect(step.field("contactId")?.value == nil && step.field("phoneNumber")?.value == nil)
        #expect(step.field("contactId")?.ambiguity == nil)
    }

    @Test func zaloChannelLooksUpTheContact() async {                       // D-297: the chat needs the number
        let sms = await resolved(draft(.sms, .open, ["recipientName": "mẹ", "body": "Con về muộn", "channel": "sms"]))
        let zalo = await resolved(draft(.sms, .open, ["recipientName": "mẹ", "body": "Con về muộn", "channel": "zalo"]))
        #expect(zalo.field("contactId")?.value == sms.field("contactId")?.value)
        #expect(zalo.field("phoneNumber")?.value == sms.field("phoneNumber")?.value)
        #expect(zalo.field("contactId")?.value != nil || zalo.field("contactId")?.ambiguity != nil)
    }

    @Test func noContactsPermissionResolvesNothing() async {                // D-185: asked later on S04
        permissions.set(.contacts, .notDetermined)
        let step = await resolved(draft(.call, .open, ["recipientName": "mẹ"]))
        #expect(step.field("contactId")?.value == nil && step.field("contactId")?.ambiguity == nil)
        #expect(permissions.requested.isEmpty)
    }

    @Test func userSetFieldsAreNotOverwritten() async {
        let d = draft(.call, .open, ["recipientName": "mẹ"])
        d.steps[0].fields[d.steps[0].fields.firstIndex { $0.id == "contactId" }!].value = "minh2"
        d.steps[0].fields[d.steps[0].fields.firstIndex { $0.id == "contactId" }!].source = .user
        let step = await resolved(d)
        #expect(step.field("contactId")?.value == "minh2")
    }

    // MARK: - Calendar delete / update (AI_PROMPTS E7)

    func event(_ id: String, _ title: String, _ start: String) -> EventSummary {
        let s = Validator.parseDateTime(start)!
        return EventSummary(id: id, title: title, start: s, end: s + 3600, isAllDay: false, isRecurring: false)
    }

    @Test func deleteFindsTheOnlyEventThatDayAndShowsIt() async throws {
        _ = calendar   // events added below
        let cal = MockCalendarService([event("ev1", "Khám nha sĩ Hoa Sen", "2026-11-13T14:00:00+07:00"),
                                       event("ev2", "Nha sĩ tái khám", "2026-11-20T14:00:00+07:00")])
        let e = TaskEngine(repository: repo, resolver: DeviceResolver(contacts: contacts, calendar: cal, permissions: permissions),
                           now: { Self.now })
        let d = draft(.calendarEvent, .delete, ["title": "nha sĩ", "startDate": "2026-11-13T00:00:00+07:00"])
        e.revalidate(stepId: d.steps[0].id, in: d)
        await e.resolveDevice(in: d)
        let step = d.steps[0]
        #expect(step.targetRef == "ev1")
        #expect(step.field("title")?.value == "Khám nha sĩ Hoa Sen")         // the real event is shown on S04
        #expect(step.field("startDate")?.value == "2026-11-13T14:00:00+07:00")
        #expect(step.state == .awaitingApproval)
        let review = ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: permissions)
        #expect(review.isDelete && review.blocker == nil)                    // still a tap on "Xác nhận xóa" (D-108)
    }

    @Test func twoEventsThatDayStayUnresolved() async {
        let cal = MockCalendarService([event("ev1", "Nha sĩ", "2026-11-13T09:00:00+07:00"),
                                       event("ev2", "Nha sĩ", "2026-11-13T15:00:00+07:00")])
        let e = TaskEngine(repository: repo, resolver: DeviceResolver(contacts: contacts, calendar: cal, permissions: permissions),
                           now: { Self.now })
        let d = draft(.calendarEvent, .delete, ["title": "nha sĩ", "startDate": "2026-11-13T00:00:00+07:00"])
        e.revalidate(stepId: d.steps[0].id, in: d)
        await e.resolveDevice(in: d)
        #expect(d.steps[0].targetRef == nil)                                 // D-106 → picker on S04 (9b)
        #expect(d.steps[0].field("title")?.value == "nha sĩ")
    }
}
