import Foundation
import Testing
@testable import EasyPhoneAI

/// S04 "Xác nhận" step 0 → S18 (ARCHITECTURE §5.1, UI_SCREENS S18, D-185).
@MainActor
@Suite("Permission step 0 (S18)")
struct PermissionStepTests {
    static let now = Validator.parseDateTime("2026-11-09T10:00:00+07:00")!
    static let reminderOK = ["title": "Uống thuốc", "dueDate": "2026-11-10T08:00:00+07:00"]

    let repo = MockTaskRepository()
    let executor = MockStepExecutor(outcome: .verified(evidence: "ek:reminder:1"))
    let engine: TaskEngine

    init() {
        engine = TaskEngine(repository: repo, executors: [.reminder: executor, .call: executor], now: { Self.now })
    }

    func open(_ kind: TaskKind, _ op: TaskOperation, _ values: [String: String],
              permissions: MockPermissionManager) -> ReviewViewModel {
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: 0.9, deviceOnly: $0.deviceOnly)
        }
        let step = TaskStep(order: 0, kind: kind, operation: op, fields: fields)
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step])
        repo.save(d)
        engine.revalidate(stepId: step.id, in: d)
        return ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions)
    }

    @Test func notDeterminedShowsExplainerAndDoesNotExecute() async {
        let perms = MockPermissionManager([.reminders: .notDetermined])
        let vm = open(.reminder, .create, Self.reminderOK, permissions: perms)
        await vm.confirm()
        #expect(vm.pendingPermission == PendingPermission(capability: .reminders, variant: .explainer))
        #expect(vm.step?.state == .awaitingApproval)
        #expect(perms.requested.isEmpty)                       // never asked before the explainer (D-185)
    }

    @Test func allowGrantedConfirms() async {
        let perms = MockPermissionManager([.reminders: .notDetermined], answer: .granted)
        let vm = open(.reminder, .create, Self.reminderOK, permissions: perms)
        await vm.confirm()
        await vm.allowPermission()
        #expect(perms.requested == [.reminders])
        #expect(vm.pendingPermission == nil)
        #expect(vm.step?.state == .succeeded)
    }

    @Test func allowDeniedShowsDeniedVariant() async {
        let perms = MockPermissionManager([.reminders: .notDetermined], answer: .denied)
        let vm = open(.reminder, .create, Self.reminderOK, permissions: perms)
        await vm.confirm()
        await vm.allowPermission()
        #expect(vm.pendingPermission == PendingPermission(capability: .reminders, variant: .denied))
        #expect(vm.step?.state == .awaitingApproval)
    }

    @Test(arguments: [PermissionStatus.denied, .restricted])
    func deniedShowsDeniedVariant(_ status: PermissionStatus) async {
        let perms = MockPermissionManager([.reminders: status])
        let vm = open(.reminder, .create, Self.reminderOK, permissions: perms)
        await vm.confirm()
        #expect(vm.pendingPermission?.variant == .denied)
        #expect(vm.step?.state == .awaitingApproval)
        vm.dismissPermission()                                  // "Để sau": nothing runs (D-100)
        #expect(vm.pendingPermission == nil && vm.step?.state == .awaitingApproval)
    }

    @Test func laterFromExplainerKeepsAwaitingApproval() async {
        let perms = MockPermissionManager([.reminders: .notDetermined])
        let vm = open(.reminder, .create, Self.reminderOK, permissions: perms)
        await vm.confirm()
        vm.dismissPermission()
        #expect(vm.pendingPermission == nil && vm.step?.state == .awaitingApproval && perms.requested.isEmpty)
    }

    @Test func kindWithoutCapabilitySkipsSheet() async {
        let perms = MockPermissionManager(Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, .notDetermined) }))
        let vm = open(.call, .open, ["recipientName": "0901234567", "phoneNumber": "+84901234567"], permissions: perms)
        await vm.confirm()
        #expect(vm.pendingPermission == nil)
        #expect(perms.requested.isEmpty)
    }

    @Test func mapping() {
        #expect(Capability.required(for: .calendarEvent) == .calendar)
        #expect(Capability.required(for: .reminder) == .reminders)
        #expect(Capability.required(for: .call) == nil && Capability.required(for: .sms) == nil)
    }

    @Test func everyCapabilityHasS18Strings() {
        for c in Capability.allCases {
            for part in ["title", "body", "fallback", "feature"] {
                let key = "perm.\(c.rawValue).\(part)"
                #expect(UserMessage(key: key).text != key, "missing \(key)")
            }
        }
        #expect(UserMessage(key: "perm.denied.title", args: ["Lịch"]).text == "Lịch chưa được cho phép")
    }
}
