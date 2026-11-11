import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.5b — ARCHITECTURE §5.1, spec §6.5 AC1–AC3, DATA_MODEL §3.5, D-105, D-248, D-249.
@MainActor
@Suite("RemindersExecutor")
struct RemindersExecutorTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-10T09:00:30+07:00")!
    static let due = "2026-11-10T20:00:00+07:00"
    let repo = MockTaskRepository()
    let reminders = MockRemindersService()
    let permissions = MockPermissionManager()

    var engine: TaskEngine {
        TaskEngine(repository: repo,
                   executors: [.reminder: RemindersExecutor(reminders: reminders, permissions: permissions,
                                                            now: { Self.now }, morningHour: { 7 })],
                   now: { Self.now })
    }

    func draft(_ op: TaskOperation, _ values: [String: String], targetRef: String? = nil) -> TaskDraft {
        let fields = FieldCatalog.mvp.fields(.reminder, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: 0.9, deviceOnly: $0.deviceOnly)
        }
        let step = TaskStep(order: 0, kind: .reminder, operation: op, fields: fields, targetRef: targetRef)
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step])
        repo.save(d)
        return d
    }

    func confirm(_ d: TaskDraft, _ e: TaskEngine) async -> ConfirmResult {
        e.revalidate(stepId: d.steps[0].id, in: d)
        return await e.confirm(stepId: d.steps[0].id, in: d)
    }

    func existing(_ title: String = "Uống thuốc") async throws -> String {
        try await reminders.save(ReminderInput(title: title, dueDate: Validator.parseDateTime(Self.due)!),
                                 stepTag: "easyphone:old", existing: nil)
    }

    @Test func createVerifiesAndTags() async throws {
        let d = draft(.create, ["title": "Uống thuốc", "dueDate": Self.due, "notes": "Sau bữa tối"])
        #expect(await confirm(d, engine) == .finished(.succeeded))
        let saved = try #require(reminders.all.first)
        #expect(d.steps[0].resultEvidence == "ek:reminder:\(saved.id)")
        #expect(saved.stepTag == "easyphone:\(d.steps[0].id.uuidString)" && saved.notes == "Sau bữa tối")
    }

    @Test func retryDoesNotCreateTwice() async throws {
        let d = draft(.create, ["title": "Uống thuốc", "dueDate": Self.due])
        _ = try await reminders.save(RemindersExecutor.input(from: d.steps[0])!, stepTag: StepTag.make(d.steps[0].id),
                                     existing: nil)
        #expect(await confirm(d, engine) == .finished(.succeeded))
        #expect(reminders.all.count == 1 && reminders.saveCount == 1)       // D-105
    }

    @Test(arguments: [PermissionStatus.denied, .notDetermined, .writeOnly])
    func needsFullAccess(_ status: PermissionStatus) async {
        permissions.set(.reminders, status)
        let d = draft(.create, ["title": "Uống thuốc", "dueDate": Self.due])
        #expect(await confirm(d, engine) == .finished(.failed))
        #expect(d.steps[0].errorCode == "permission.reminders.denied")
        #expect(reminders.saveCount == 0)
    }

    @Test func updateAndDelete() async throws {
        let id = try await existing()
        let u = draft(.update, ["title": "Uống thuốc huyết áp", "dueDate": "2026-11-10T21:00:00+07:00"], targetRef: id)
        #expect(await confirm(u, engine) == .finished(.succeeded))
        #expect(reminders.all[0].title == "Uống thuốc huyết áp")
        let del = draft(.delete, [:], targetRef: id)
        #expect(await confirm(del, engine) == .finished(.succeeded))
        #expect(del.steps[0].resultEvidence == "ek:reminder:\(id)" && reminders.deleted == [id])
        let again = draft(.delete, [:], targetRef: id)                     // already gone → done, no second call
        #expect(await confirm(again, engine) == .finished(.succeeded))
        #expect(reminders.deleted == [id])
    }

    @Test func completeAndUndo() async throws {                              // D-248
        let id = try await existing()
        let done = draft(.complete, ["completed": "true"], targetRef: id)
        #expect(await confirm(done, engine) == .finished(.succeeded))
        #expect(try await reminders.find(identifier: id)?.isCompleted == true)
        let undo = draft(.complete, ["completed": "false"], targetRef: id)
        #expect(await confirm(undo, engine) == .finished(.succeeded))
        #expect(try await reminders.find(identifier: id)?.isCompleted == false)
    }

    @Test func snoozeMovesTheDueDate() async throws {
        let id = try await existing()
        let s = draft(.snooze, ["snoozeOption": "hour1"], targetRef: id)
        #expect(await confirm(s, engine) == .finished(.succeeded))
        #expect(try await reminders.find(identifier: id)?.dueDate == Validator.parseDateTime("2026-11-10T10:00:00+07:00"))
        // Result text "Đã dời lời nhắc tới {time}" uses the executor's rule at the success time.
        let review = ReviewViewModel(draftId: s.id, repository: repo, engine: engine, permissions: permissions,
                                     snoozeMorningHour: 7)
        #expect(review.snoozedTo(s.steps[0]) == "Thứ Ba, 10/11 lúc 10:00")
    }

    @Test func snoozeRule() {
        let at = { Validator.parseDateTime($0)! }
        #expect(RemindersExecutor.snoozeDate("min15", from: Self.now, morningHour: 7, timeZone: Self.tz) == at("2026-11-10T09:15:00+07:00"))
        #expect(RemindersExecutor.snoozeDate("hour1", from: Self.now, morningHour: 7, timeZone: Self.tz) == at("2026-11-10T10:00:00+07:00"))
        #expect(RemindersExecutor.snoozeDate("tomorrowMorning", from: at("2026-11-10T23:50:00+07:00"), morningHour: 7,
                                             timeZone: Self.tz) == at("2026-11-11T07:00:00+07:00"))
        #expect(RemindersExecutor.snoozeDate("never", from: Self.now, morningHour: 7, timeZone: Self.tz) == nil)
    }

    @Test func writeFailureFails() async {
        reminders.failNextWrite()
        let d = draft(.create, ["title": "Uống thuốc", "dueDate": Self.due])
        #expect(await confirm(d, engine) == .finished(.failed))
        #expect(d.steps[0].errorCode == "eventkit.saveFailed")
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions)
        #expect(vm.errorMessage(d.steps[0]) == "Không lưu được vào Lời nhắc. Bạn thử lại nhé.")
    }
}
