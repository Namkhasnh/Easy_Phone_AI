import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.9b1 — S04 contact rows + S06 picker (UI_SCREENS S04 / S06, D-106, D-185, D-251, DATA_MODEL §7.3).
@MainActor
@Suite("S04 contact rows + S06 picker")
struct ReviewPickerTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    static let people: [ContactRecord] = [
        ContactRecord(id: "minh1", givenName: "Minh", middleName: "Văn", familyName: "Nguyễn", phoneCount: 2),
        ContactRecord(id: "minh2", givenName: "Mính", familyName: "Trần", phoneCount: 1),
    ]
    static let phones: [String: [PhoneEntry]] = [
        "minh1": [PhoneEntry(label: "di động", number: "0901 234 567"), PhoneEntry(label: "nhà", number: "0912 000 111")],
        "minh2": [PhoneEntry(label: nil, number: "0987 654 321")],
    ]

    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()
    let contacts = MockContactsService(people, phones: phones)
    let engine: TaskEngine

    init() {
        engine = TaskEngine(repository: repo,
                            resolver: DeviceResolver(contacts: contacts, calendar: MockCalendarService(), permissions: permissions),
                            now: { Self.now })
    }

    func callDraft(_ name: String) async -> ReviewViewModel {
        let fields = FieldCatalog.mvp.fields(.call, .open).map {
            Field(id: $0.id, type: $0.type, value: $0.id == "recipientName" ? name : nil, source: .ai, confidence: 0.9,
                  deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "Gọi \(name)", timeZoneId: "Asia/Ho_Chi_Minh",
                          steps: [TaskStep(order: 0, kind: .call, operation: .open, fields: fields)])
        repo.save(d)
        engine.revalidate(stepId: d.steps[0].id, in: d)
        await engine.resolveDevice(in: d)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions, contacts: contacts)
        await vm.loadContactName()
        return vm
    }

    @Test func pickContactThenNumber() async throws {
        let vm = await callDraft("anh Minh")
        #expect(vm.blocker == .ambiguity)
        let row = try #require(vm.visibleFields.first { $0.id == "contactId" })
        await vm.tapRow(row)                                                    // ambiguity → S06
        #expect(vm.picking?.ambiguity.question == "Bạn muốn gọi anh Minh nào?")
        #expect(vm.picking?.ambiguity.candidates.count == 2)                    // no default selection
        await vm.pick(vm.picking!.ambiguity.candidates.first { $0.id == "minh1" }!, fieldId: "contactId")
        #expect(vm.step?.field("contactId")?.value == "minh1")
        #expect(vm.displayValue(vm.step!.field("contactId")!) == "Nguyễn Văn Minh")
        #expect(vm.pickingFieldId == "phoneNumber")                            // 2 numbers → second picker
        #expect(vm.picking?.ambiguity.candidates.map(\.title) == ["di động: •••• 567", "nhà: •••• 111"])
        await vm.pick(vm.picking!.ambiguity.candidates[1], fieldId: "phoneNumber")
        #expect(vm.step?.field("phoneNumber")?.value == "+84912000111")
        #expect(vm.blocker == nil && vm.step?.state == .awaitingApproval)
    }

    @Test func pickContactWithOneNumberFillsAndMasks() async throws {
        let vm = await callDraft("Minh")
        vm.pickingFieldId = "contactId"
        await vm.pick(vm.picking!.ambiguity.candidates.first { $0.id == "minh2" }!, fieldId: "contactId")
        let phone = try #require(vm.step?.field("phoneNumber"))
        #expect(phone.value == "+84987654321")
        #expect(vm.displayValue(phone) == "•••• 321")                           // number from Contacts is masked
        #expect(vm.pickingFieldId == nil && vm.blocker == nil)
    }

    /// Owner iPhone test 2026-11-11: the sheet closing cleared `pickingFieldId` first, so the pick was lost.
    @Test func pickWorksAfterTheSheetClosed() async throws {
        let vm = await callDraft("Nguyễn Văn Minh")                            // one contact, two numbers
        vm.openPendingPicker()                                                  // S06 opens by itself
        #expect(vm.pickingFieldId == "phoneNumber")
        let candidate = vm.picking!.ambiguity.candidates[0]
        vm.pickingFieldId = nil                                                 // what closing the sheet does
        await vm.pick(candidate, fieldId: "phoneNumber")
        #expect(vm.step?.field("phoneNumber")?.value == "+84901234567")
        #expect(vm.blocker == nil)
    }

    /// Owner's contact "bôm": "034 7676916" + "+84 34 7676916" = one number → filled, no question.
    @Test func sameNumberTwiceIsNotAChoice() async throws {
        let c = MockContactsService([ContactRecord(id: "bom", givenName: "bôm", familyName: "", phoneCount: 2)],
                                    phones: ["bom": [PhoneEntry(label: "phone", number: "034 7676916"),
                                                     PhoneEntry(label: "mobile", number: "+84 34 7676916")]])
        let e = TaskEngine(repository: repo,
                           resolver: DeviceResolver(contacts: c, calendar: MockCalendarService(), permissions: permissions),
                           now: { Self.now })
        let fields = FieldCatalog.mvp.fields(.call, .open).map {
            Field(id: $0.id, type: $0.type, value: $0.id == "recipientName" ? "bôm" : nil, source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .text, originalInput: "Gọi bôm", steps: [TaskStep(order: 0, kind: .call, operation: .open, fields: fields)])
        repo.save(d)
        await e.resolveDevice(in: d)
        #expect(d.steps[0].field("phoneNumber")?.value == "+84347676916")
        #expect(d.steps[0].field("phoneNumber")?.ambiguity == nil)
        #expect(d.steps[0].state == .awaitingApproval)
    }

    @Test func contactRowAsksContactsPermissionFirst() async throws {
        permissions.set(.contacts, .notDetermined)
        let vm = await callDraft("anh Minh")                                   // resolver skipped: no permission
        let row = try #require(vm.visibleFields.first { $0.id == "contactId" })
        #expect(row.ambiguity == nil && row.value == nil)
        await vm.tapRow(row)
        #expect(vm.pendingPermission == PendingPermission(capability: .contacts, variant: .explainer))
        #expect(permissions.requested.isEmpty)                                 // D-185
        await vm.allowPermission()                                             // → request → resolve → S06
        #expect(permissions.requested == [.contacts])
        #expect(vm.pickingFieldId == "contactId")
        #expect(vm.step?.state != .processing)                                 // never executed by this
    }

    @Test func deniedContactsShowsDenied() async throws {
        permissions.set(.contacts, .denied)
        let vm = await callDraft("anh Minh")
        await vm.tapRow(vm.visibleFields.first { $0.id == "contactId" }!)
        #expect(vm.pendingPermission?.variant == .denied)
    }

    @Test func pickAfterApprovalResetsIt() async throws {                     // D-101
        let vm = await callDraft("Trần Mính")
        #expect(vm.step?.state == .awaitingApproval)
        vm.pickingFieldId = nil
        let d = try #require(vm.draft)
        d.steps[0].fields[d.steps[0].fields.firstIndex { $0.id == "contactId" }!].ambiguity =
            Ambiguity(kind: .contact, question: "?", candidates: [Candidate(id: "minh1", title: "Nguyễn Văn Minh")])
        vm.pickingFieldId = "contactId"
        await vm.pick(vm.picking!.ambiguity.candidates[0], fieldId: "contactId")
        #expect(vm.step?.field("contactId")?.source == .user)
        #expect(vm.step?.history.last?.event == .userEdited || vm.step?.history.contains { $0.event == .userEdited } == true)
    }
}
