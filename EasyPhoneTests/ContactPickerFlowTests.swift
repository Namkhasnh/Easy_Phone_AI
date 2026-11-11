import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.9c — S06 "Chọn trong danh bạ" (iOS picker, no Contacts access needed) + limited access (UI_SCREENS S06).
@MainActor
@Suite("S06 Chọn trong danh bạ")
struct ContactPickerFlowTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()

    func vm(_ spoken: String, contacts: MockContactsService = MockContactsService(),
            local: MockLocalDataRepository? = MockLocalDataRepository()) async -> ReviewViewModel {
        let e = TaskEngine(repository: repo,
                           resolver: DeviceResolver(contacts: contacts, calendar: MockCalendarService(), permissions: permissions),
                           now: { Self.now })
        let fields = FieldCatalog.mvp.fields(.call, .open).map {
            Field(id: $0.id, type: $0.type, value: $0.id == "recipientName" ? spoken : nil, source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "Gọi \(spoken)",
                          steps: [TaskStep(order: 0, kind: .call, operation: .open, fields: fields)])
        repo.save(d)
        await e.resolveDevice(in: d)
        return ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: permissions, contacts: contacts,
                               localData: local)
    }

    static let lan = PickedContact(id: "lan", displayName: "Nguyễn Thị Lan",
                                   phones: [PhoneEntry(label: "di động", number: "0903 333 444")])

    @Test func noMatchOffersTheContactPickerAndAPickFillsEverything() async throws {
        let vm = await vm("mẹ")                                                 // nobody named "mẹ"
        #expect(vm.step?.field("contactId")?.ambiguity?.candidates.isEmpty == true)
        vm.openPendingPicker()
        #expect(vm.pickingFieldId == nil)                                       // empty list does not auto-open
        vm.pickingFieldId = "contactId"
        #expect(vm.canOpenContacts)
        vm.openContacts()
        #expect(vm.showsContactPicker && vm.pickingFieldId == nil)
        vm.pickedFromContacts(Self.lan)
        #expect(vm.step?.field("contactId")?.value == "lan")
        #expect(vm.step?.field("phoneNumber")?.value == "+84903333444")
        #expect(vm.displayValue(vm.step!.field("contactId")!) == "Nguyễn Thị Lan")
        #expect(vm.blocker == nil && vm.step?.state == .awaitingApproval)
        #expect(vm.nicknameOffer?.nickname == "mẹ")                            // then "Lưu “mẹ” là Nguyễn Thị Lan…"
    }

    @Test func deniedContactsGoesStraightToTheSystemPicker() async {
        permissions.set(.contacts, .denied)
        let vm = await vm("mẹ")
        await vm.tapRow(vm.visibleFields.first { $0.id == "contactId" }!)
        #expect(vm.showsContactPicker && vm.pendingPermission == nil)          // no dead end, no access needed
        vm.pickedFromContacts(PickedContact(id: "x", displayName: "Bác Ba",
                                            phones: [PhoneEntry(label: "nhà", number: "0912 111 222"),
                                                     PhoneEntry(label: "di động", number: "0988 777 666")]))
        #expect(vm.pickingFieldId == "phoneNumber")                             // two numbers → choose one
        #expect(vm.picking?.ambiguity.candidates.map(\.title) == ["nhà: •••• 222", "di động: •••• 666"])
        await vm.loadContactName()                                              // no access: the picked name stays
        #expect(vm.contactName == "Bác Ba")
    }

    @Test func limitedAccessShowsAppleSearchForTheSpokenName() async {
        permissions.set(.contacts, .limited)
        let vm = await vm("anh Hùng")
        vm.pickingFieldId = "contactId"
        #expect(vm.limitedQuery == "hung")
        permissions.set(.contacts, .granted)
        #expect(vm.limitedQuery == nil)
    }
}
