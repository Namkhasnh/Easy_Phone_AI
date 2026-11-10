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

/// S03 mic step 0 → S18 for microphone, then speech (D-185); S15 "Quyền truy cập" rows (UI_SCREENS S15, §10.4).
@MainActor
@Suite("Permission S03 mic + S15 rows")
struct PermissionMicAndSettingsTests {
    let repo = MockTaskRepository()
    let speech = MockSpeechService()
    let local = MockLocalDataRepository()

    func conversation(_ perms: MockPermissionManager) -> ConversationViewModel {
        ConversationViewModel(draftId: nil, repository: repo, speech: speech, api: MockAPIClient(), tts: MockTTSService(),
                              localData: local, permissions: perms)
    }

    @Test func micAsksMicrophoneThenSpeechThenRecords() async {
        let perms = MockPermissionManager([.microphone: .notDetermined, .speech: .notDetermined], answer: .granted)
        let vm = conversation(perms)
        await vm.onAppear()
        #expect(vm.pendingPermission == PendingPermission(capability: .microphone, variant: .explainer))
        #expect(speech.startCount == 0 && perms.requested.isEmpty)       // nothing before the explainer
        await vm.allowPermission()
        #expect(vm.pendingPermission == PendingPermission(capability: .speech, variant: .explainer))
        #expect(speech.startCount == 0)
        await vm.allowPermission()
        #expect(perms.requested == [.microphone, .speech])
        #expect(vm.pendingPermission == nil)
        #expect(speech.startCount == 1)
        #expect(vm.text == "Nhắc tôi 8 giờ sáng mai uống thuốc")
    }

    @Test func deniedMicShowsDeniedAndKeepsKeyboard() async {
        let perms = MockPermissionManager([.microphone: .denied])
        let vm = conversation(perms)
        await vm.onAppear()
        #expect(vm.pendingPermission == PendingPermission(capability: .microphone, variant: .denied))
        #expect(vm.mode == .transcript && speech.startCount == 0)
        vm.dismissPermission()
        #expect(vm.pendingPermission == nil && vm.mode == .transcript)    // fallback: type (S18 "Gõ chữ")
    }

    @Test func refusingTheSystemAlertShowsDenied() async {
        let perms = MockPermissionManager([.speech: .notDetermined], answer: .denied)
        let vm = conversation(perms)
        await vm.onAppear()
        await vm.allowPermission()
        #expect(vm.pendingPermission == PendingPermission(capability: .speech, variant: .denied))
        #expect(speech.startCount == 0)
    }

    @Test func settingsRowsReadWithoutAskingAndRefresh() {
        let perms = MockPermissionManager([.calendar: .writeOnly, .contacts: .limited, .camera: .notDetermined])
        let vm = SettingsViewModel(localData: local, drafts: repo, auth: MockAuthService(), permissions: perms)
        #expect(vm.permissionStatuses.map(\.capability) == Capability.allCases)
        #expect(vm.permissionStatuses.first { $0.capability == .calendar }?.status == .writeOnly)
        #expect(perms.requested.isEmpty)                                  // S15 never prompts (D-185)
        perms.set(.calendar, .denied)                                     // changed in iOS Settings
        vm.refreshPermissions()
        #expect(vm.permissionStatuses.first { $0.capability == .calendar }?.status == .denied)
        for status in [PermissionStatus.notDetermined, .granted, .limited, .writeOnly, .denied, .restricted] {
            #expect(UserMessage(key: status.labelKey).text != status.labelKey, "missing \(status.labelKey)")
        }
    }
}
