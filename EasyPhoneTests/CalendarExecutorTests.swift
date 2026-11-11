import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.3 — ARCHITECTURE §5.1 steps 4–6, spec §6.4 AC3, DATA_MODEL §3.5, D-105, D-124, D-225, D-249.
@MainActor
@Suite("CalendarExecutor")
struct CalendarExecutorTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    static let start = "2026-11-13T14:00:00+07:00"
    let repo = MockTaskRepository()
    let calendar = MockCalendarService()
    let permissions = MockPermissionManager()

    var engine: TaskEngine {
        TaskEngine(repository: repo,
                   executors: [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions)],
                   now: { Self.now })
    }

    func draft(_ op: TaskOperation, _ values: [String: String], targetRef: String? = nil) -> TaskDraft {
        let fields = FieldCatalog.mvp.fields(.calendarEvent, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: 0.9, deviceOnly: $0.deviceOnly)
        }
        let step = TaskStep(order: 0, kind: .calendarEvent, operation: op, fields: fields, targetRef: targetRef)
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step])
        repo.save(d)
        return d
    }

    func confirm(_ d: TaskDraft, with e: TaskEngine) async -> ConfirmResult {
        e.revalidate(stepId: d.steps[0].id, in: d)
        return await e.confirm(stepId: d.steps[0].id, in: d)
    }

    static let dentist = ["title": "Khám răng", "startDate": start, "location": "Nha khoa Hoa Sen", "alertMinutesBefore": "60"]

    @Test func createSavesTagsAndVerifies() async throws {
        let d = draft(.create, Self.dentist)
        #expect(await confirm(d, with: engine) == .finished(.succeeded))
        let saved = try #require(calendar.all.first)
        #expect(d.steps[0].resultEvidence == "ek:event:\(saved.id)")              // D-124, §3.5
        #expect(saved.stepTag == "easyphone:\(d.steps[0].id.uuidString)")         // D-225
        #expect(saved.end == saved.start + 3600)                                    // endDate default +60 min
        #expect(saved.alertMinutesBefore == 60 && saved.location == "Nha khoa Hoa Sen")
    }

    @Test func retryFindsTheEventByTagInsteadOfCreatingAgain() async throws {
        let d = draft(.create, Self.dentist)
        let e = engine
        _ = try await calendar.save(CalendarExecutor.input(from: d.steps[0])!,
                                    stepTag: StepTag.make(d.steps[0].id), existing: nil)   // saved, result lost
        #expect(await confirm(d, with: e) == .finished(.succeeded))
        #expect(calendar.all.count == 1 && calendar.saveCount == 1)                 // D-105: no duplicate
    }

    @Test func saveFailureFailsWithEventKitCode() async {
        calendar.failNextSave()
        let d = draft(.create, Self.dentist)
        #expect(await confirm(d, with: engine) == .finished(.failed))
        #expect(d.steps[0].errorCode == "eventkit.saveFailed")
        #expect(d.steps[0].resultEvidence == nil)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions)
        #expect(vm.errorMessage(d.steps[0]) == "Không lưu được vào Lịch. Bạn thử lại nhé.")
    }

    @Test(arguments: [PermissionStatus.denied, .restricted, .notDetermined])
    func notUsablePermissionFails(_ status: PermissionStatus) async {
        permissions.set(.calendar, status)
        let d = draft(.create, Self.dentist)
        #expect(await confirm(d, with: engine) == .finished(.failed))
        #expect(d.steps[0].errorCode == "permission.calendar.denied")              // D-249
        #expect(calendar.saveCount == 0)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions)
        #expect(vm.errorMessage(d.steps[0]) == "Ứng dụng chưa được phép dùng Lịch.")
    }

    @Test func writeOnlyCreatesButCannotUpdateOrDelete() async {
        permissions.set(.calendar, .writeOnly)
        calendar.setAccess(.writeOnly)
        let d = draft(.create, Self.dentist)
        #expect(await confirm(d, with: engine) == .finished(.succeeded))
        #expect(calendar.saveCount == 1)
        let u = draft(.update, Self.dentist, targetRef: "mock-event-1")
        #expect(await confirm(u, with: engine) == .finished(.failed))
        #expect(u.steps[0].errorCode == "permission.calendar.denied")
    }

    @Test func updateChangesTheTargetEvent() async throws {
        let id = try await calendar.save(EventInput(title: "Khám răng", start: Validator.parseDateTime(Self.start)!,
                                                    end: Validator.parseDateTime(Self.start)! + 3600),
                                         stepTag: "easyphone:old", existing: nil)
        var values = Self.dentist
        values["startDate"] = "2026-11-13T16:00:00+07:00"
        let d = draft(.update, values, targetRef: id)
        #expect(await confirm(d, with: engine) == .finished(.succeeded))
        #expect(d.steps[0].resultEvidence == "ek:event:\(id)")
        #expect(calendar.all.count == 1)
        #expect(calendar.all[0].start == Validator.parseDateTime("2026-11-13T16:00:00+07:00"))
    }

    @Test func updateOfMissingEventFails() async {
        let d = draft(.update, Self.dentist, targetRef: "gone")
        #expect(await confirm(d, with: engine) == .finished(.failed))
        #expect(d.steps[0].errorCode == "eventkit.saveFailed")
    }

    @Test func deleteRemovesAndIsIdempotent() async throws {
        let id = try await calendar.save(EventInput(title: "Khám răng", start: .now + 3600, end: .now + 7200),
                                         stepTag: "easyphone:x", existing: nil)
        let d = draft(.delete, ["title": "Khám răng"], targetRef: id)
        #expect(await confirm(d, with: engine) == .finished(.succeeded))
        #expect(d.steps[0].resultEvidence == "ek:deleted:\(id)")
        #expect(calendar.deleted == [id])
        // Already gone (retry after the delete went through) → success without a second delete call.
        let again = draft(.delete, ["title": "Khám răng"], targetRef: id)
        #expect(await confirm(again, with: engine) == .finished(.succeeded))
        #expect(calendar.deleted == [id])
    }

    @Test func inputMapping() {
        let d = draft(.create, ["title": " Họp lớp ", "startDate": Self.start, "endDate": "2026-11-13T17:30:00+07:00",
                                "allDay": "false", "notes": ""])
        let input = CalendarExecutor.input(from: d.steps[0])
        #expect(input?.title == "Họp lớp")
        #expect(input?.end == Validator.parseDateTime("2026-11-13T17:30:00+07:00"))
        #expect(input?.notes == nil && input?.isAllDay == false && input?.alertMinutesBefore == nil)
        #expect(CalendarExecutor.input(from: draft(.create, ["title": "x"]).steps[0]) == nil)
        #expect(CalendarExecutor.eventId("ek:event:ABC") == "ABC" && CalendarExecutor.eventId("ek:reminder:A") == nil)
    }
}
