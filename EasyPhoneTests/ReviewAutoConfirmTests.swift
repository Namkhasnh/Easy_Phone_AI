import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.23 — D-299: optional auto-confirm after a 3 s countdown, safe kinds only, default off; delete keeps the tap (D-108).
@MainActor
@Suite("S04 auto-confirm (D-299)")
struct ReviewAutoConfirmTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    let repo = MockTaskRepository()
    let local = MockLocalDataRepository()
    let calls = MockCallService()
    let permissions = MockPermissionManager([.contacts: .granted, .calendar: .granted])
    let engine: TaskEngine

    init() {
        engine = TaskEngine(repository: repo, executors: [.call: CallExecutor(calls: calls)], now: { Self.now })
    }

    func draft(_ kind: TaskKind, _ op: TaskOperation, _ values: [String: String], targetRef: String? = nil) -> TaskDraft {
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "x",
                          steps: [TaskStep(order: 0, kind: kind, operation: op, fields: fields, targetRef: targetRef)])
        repo.save(d)
        engine.revalidate(stepId: d.steps[0].id, in: d)
        return d
    }

    func model(_ d: TaskDraft) -> ReviewViewModel {
        ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions, localData: local,
                        now: { Self.now }, autoConfirmTick: .milliseconds(5))
    }

    static let mom = ["recipientName": "mẹ", "contactId": "lan", "phoneNumber": "+84903333444"]

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func offByDefaultNothingRuns() async {
        let d = draft(.call, .open, Self.mom)
        let vm = model(d)
        vm.startAutoConfirmIfAllowed()
        #expect(vm.autoConfirmSeconds == nil)
        #expect(d.steps[0].state == .awaitingApproval)
    }

    @Test func onCountsDownThenRunsTheSameConfirm() async {
        local.settings().autoConfirm = true
        let d = draft(.call, .open, Self.mom)
        let vm = model(d)
        vm.startAutoConfirmIfAllowed()
        #expect(vm.autoConfirmSeconds == ReviewViewModel.autoConfirmDelay)
        await waitUntil { d.steps[0].state != .awaitingApproval }
        #expect(d.steps[0].state == .handedOff)                                  // still never succeeded (D-102)
        #expect(calls.calls == ["+84903333444"])
        #expect(vm.autoConfirmSeconds == nil)
    }

    @Test func stopKeepsTheStepWaiting() async throws {
        local.settings().autoConfirm = true
        let d = draft(.call, .open, Self.mom)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions,
                                 localData: local, now: { Self.now }, autoConfirmTick: .seconds(30))
        vm.startAutoConfirmIfAllowed()
        vm.cancelAutoConfirm()                                                   // "Để tôi xem lại"
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.autoConfirmSeconds == nil)
        #expect(d.steps[0].state == .awaitingApproval)
        vm.startAutoConfirmIfAllowed()                                           // not restarted on this screen
        #expect(vm.autoConfirmSeconds == nil)
        #expect(calls.calls.isEmpty)
    }

    @Test func editCancelsTheCountdown() {
        local.settings().autoConfirm = true
        let d = draft(.call, .open, Self.mom)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions,
                                 localData: local, now: { Self.now }, autoConfirmTick: .seconds(30))
        vm.startAutoConfirmIfAllowed()
        vm.startEdit()
        #expect(vm.autoConfirmSeconds == nil)
    }

    @Test func deleteAndUpdateAlwaysNeedTheTap() {
        local.settings().autoConfirm = true
        let delete = draft(.calendarEvent, .delete, [:], targetRef: "ev1")
        let vm = model(delete)
        vm.startAutoConfirmIfAllowed()
        #expect(vm.autoConfirmSeconds == nil)                                    // D-108
        #expect(!ReviewViewModel.isAutoConfirmable(.calendarEvent, .update))
        #expect(!ReviewViewModel.isAutoConfirmable(.reminder, .complete))
        #expect(!ReviewViewModel.isAutoConfirmable(.reminder, .snooze))
        #expect(ReviewViewModel.isAutoConfirmable(.calendarEvent, .create))
    }

    @Test func missingInfoOrUnaskedPermissionDoesNotCountDown() {
        local.settings().autoConfirm = true
        let missing = draft(.call, .open, ["recipientName": "mẹ"])               // no number yet → still asks
        #expect(!model(missing).canAutoConfirm)
        let event = draft(.calendarEvent, .create, ["title": "Khám răng", "startDate": "2026-11-13T14:00:00+07:00"])
        permissions.set(.calendar, .notDetermined)                               // S18 explainer first, never on a timer
        #expect(!model(event).canAutoConfirm)
    }
}
