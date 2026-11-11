import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.9b2 — S04 event choice (`ambiguity.event`, D-106) + `picker.saveNickname` (spec §6.6 AC3).
@MainActor
@Suite("S04 event choice + save nickname")
struct ReviewEventChoiceTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    static func event(_ id: String, _ title: String, _ start: String) -> EventSummary {
        let s = Validator.parseDateTime(start)!
        return EventSummary(id: id, title: title, start: s, end: s + 3600, isAllDay: false, isRecurring: false)
    }

    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()
    let calendar = MockCalendarService([event("ev1", "Nha sĩ", "2026-11-13T09:00:00+07:00"),
                                        event("ev2", "Nha sĩ", "2026-11-13T15:00:00+07:00")])
    let engine: TaskEngine

    init() {
        engine = TaskEngine(repository: repo,
                            executors: [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions)],
                            resolver: DeviceResolver(contacts: MockContactsService(), calendar: calendar, permissions: permissions),
                            now: { Self.now })
    }

    func deleteDraft() async -> ReviewViewModel {
        let fields = FieldCatalog.mvp.fields(.calendarEvent, .delete).map {
            Field(id: $0.id, type: $0.type, value: ["title": "nha sĩ", "startDate": "2026-11-13T00:00:00+07:00"][$0.id],
                  source: .ai, confidence: 0.8, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "Hủy lịch nha sĩ thứ Sáu", timeZoneId: "Asia/Ho_Chi_Minh",
                          steps: [TaskStep(order: 0, kind: .calendarEvent, operation: .delete, fields: fields)])
        repo.save(d)
        engine.revalidate(stepId: d.steps[0].id, in: d)
        await engine.resolveDevice(in: d)                                        // two that day → unresolved
        return ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions, calendar: calendar)
    }

    @Test func twoEventsThatDayAskWhichOneThenDelete() async throws {
        let vm = await deleteDraft()
        #expect(vm.needsEventChoice && vm.blocker == .missing)
        await vm.chooseEvent()
        let choice = try #require(vm.eventChoice)
        #expect(choice.question == "Bạn muốn chọn lịch hẹn nào?")
        #expect(Set(choice.candidates.map(\.id)) == ["ev1", "ev2"])            // no default (D-106)
        #expect(choice.candidates.first { $0.id == "ev2" }?.subtitle == "Thứ Sáu, 13/11 lúc 15:00")
        vm.pickEvent(choice.candidates.first { $0.id == "ev2" }!)
        #expect(vm.eventChoice == nil && !vm.needsEventChoice)
        #expect(vm.step?.targetRef == "ev2")
        #expect(vm.step?.field("startDate")?.value == "2026-11-13T15:00:00+07:00")   // the real event is shown
        #expect(vm.blocker == nil && calendar.deleted.isEmpty)                 // still needs "Xác nhận xóa"
        await vm.confirm()
        #expect(calendar.deleted == ["ev2"])
    }

    @Test func calendarPermissionFirst() async throws {
        permissions.set(.calendar, .notDetermined)
        let vm = await deleteDraft()
        await vm.chooseEvent()
        #expect(vm.pendingPermission == PendingPermission(capability: .calendar, variant: .explainer))
        #expect(permissions.requested.isEmpty)
        await vm.allowPermission()                                             // granted → S06, nothing executed
        #expect(vm.eventChoice?.candidates.count == 2)
        #expect(calendar.deleted.isEmpty && vm.step?.state != .processing)
    }

    // MARK: - Save nickname (spec §6.6 AC3)

    func callVM(_ spoken: String, localData: MockLocalDataRepository) async -> ReviewViewModel {
        let contacts = MockContactsService([ContactRecord(id: "lan", givenName: "Lan", middleName: "Thị", familyName: "Nguyễn", phoneCount: 1),
                                            ContactRecord(id: "hoa", givenName: "Hoa", familyName: "Lê", phoneCount: 1)],
                                           phones: ["lan": [PhoneEntry(label: "di động", number: "0903 333 444")],
                                                    "hoa": [PhoneEntry(label: "di động", number: "0904 444 555")]])
        let e = TaskEngine(repository: repo,
                           resolver: DeviceResolver(contacts: contacts, calendar: calendar, permissions: permissions),
                           now: { Self.now })
        let fields = FieldCatalog.mvp.fields(.call, .open).map {
            Field(id: $0.id, type: $0.type, value: $0.id == "recipientName" ? spoken : nil, source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "Gọi \(spoken)", steps: [TaskStep(order: 0, kind: .call, operation: .open, fields: fields)])
        repo.save(d)
        await e.resolveDevice(in: d)
        d.steps[0].fields[d.steps[0].fields.firstIndex { $0.id == "contactId" }!].ambiguity =
            Ambiguity(kind: .contact, question: "?", candidates: [Candidate(id: "lan", title: "Nguyễn Thị Lan")])
        return ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: permissions, contacts: contacts,
                               localData: localData)
    }

    @Test func pickingForAKinshipWordOffersANicknameAndSavesIt() async throws {
        let local = MockLocalDataRepository()
        let vm = await callVM("mẹ", localData: local)
        await vm.pick(Candidate(id: "lan", title: "Nguyễn Thị Lan"), fieldId: "contactId")
        let offer = try #require(vm.nicknameOffer)
        #expect(offer == .init(nickname: "mẹ", contactId: "lan", contactName: "Nguyễn Thị Lan"))
        #expect(UserMessage(key: "picker.saveNickname", args: [offer.nickname, offer.contactName]).text
                == "Lưu “mẹ” là Nguyễn Thị Lan để lần sau mình nhận ra?")
        vm.saveNickname()
        #expect(vm.nicknameOffer == nil)
        #expect(local.nickname(matching: "Mẹ")?.contactId == "lan")             // next time "mẹ" resolves by itself
    }

    @Test func pickingForThePersonsOwnNameOffersNothing() async {
        let vm = await callVM("chị Lan", localData: MockLocalDataRepository())
        await vm.pick(Candidate(id: "lan", title: "Nguyễn Thị Lan"), fieldId: "contactId")
        #expect(vm.nicknameOffer == nil)
    }

    @Test func noThanksStoresNothing() async {
        let local = MockLocalDataRepository()
        let vm = await callVM("sếp", localData: local)
        await vm.pick(Candidate(id: "lan", title: "Nguyễn Thị Lan"), fieldId: "contactId")
        vm.dismissNicknameOffer()
        #expect(vm.nicknameOffer == nil && local.nicknames().isEmpty)
    }
}
