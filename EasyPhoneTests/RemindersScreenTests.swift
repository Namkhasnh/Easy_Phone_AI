import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.6a — UI_SCREENS S12, spec §6.5 AC3, D-107, D-248, D-185.
@MainActor
@Suite("S12 Reminders")
struct RemindersScreenTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-13T10:00:00+07:00")!
    static func r(_ id: String, _ title: String, _ hours: Double?, recurring: Bool = false) -> ReminderSummary {
        ReminderSummary(id: id, title: title, dueDate: hours.map { now + $0 * 3600 }, isCompleted: false, isRecurring: recurring)
    }

    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()
    let reminders: MockRemindersService
    let engine: TaskEngine

    init() {
        reminders = MockRemindersService([Self.r("a", "Uống thuốc", -1), Self.r("b", "Gọi con", 2), Self.r("c", "Mua rau", nil),
                                          Self.r("d", "Tập thể dục", 1, recurring: true)])
        engine = TaskEngine(repository: repo,
                            executors: [.reminder: RemindersExecutor(reminders: reminders, permissions: permissions,
                                                                     now: { Self.now })],
                            now: { Self.now })
    }

    func model(_ perms: MockPermissionManager? = nil) -> RemindersViewModel {
        RemindersViewModel(reminders: reminders, permissions: perms ?? permissions, repository: repo, engine: engine,
                           now: { Self.now }, timeZone: Self.tz)
    }

    @Test func sectionsOverdueThenUpcoming() async {
        let vm = model()
        await vm.load()
        #expect(vm.sections.map(\.kind) == [.overdue, .upcoming])
        #expect(vm.sections[0].rows.map(\.id) == ["a"])
        #expect(vm.sections[1].rows.map(\.id) == ["b", "c"])                    // undated last, recurring hidden
        #expect(vm.sections[0].rows[0].due == "Thứ Sáu, 13/11 lúc 09:00")
        #expect(vm.sections[1].rows[1].due == nil)
    }

    @Test func oneTapCompleteThenUndo() async throws {
        let vm = model()
        await vm.load()
        await vm.complete("a")                                                   // one tap, no S04 (D-107)
        #expect(try await reminders.find(identifier: "a")?.isCompleted == true)
        #expect(vm.sections.map(\.kind) == [.upcoming])
        let toast = try #require(vm.toast)
        #expect(toast.message.key == "reminders.completed.toast" && toast.undo != nil)
        let draft = try #require(repo.history(group: .done).first)              // recorded as a succeeded step
        #expect(draft.steps[0].operation == .complete && draft.steps[0].field("completed")?.value == "true")
        #expect(draft.steps[0].resultEvidence == "ek:reminder:a")
        await vm.undo(reminders.all.first { $0.id == "a" }!)                     // "Hoàn tác" (D-248)
        #expect(try await reminders.find(identifier: "a")?.isCompleted == false)
        #expect(vm.sections.first?.rows.map(\.id) == ["a"])
    }

    @Test func failedCompleteShowsErrorAndKeepsRow() async throws {
        reminders.failNextWrite()
        let vm = model()
        await vm.load()
        await vm.complete("a")
        #expect(try await reminders.find(identifier: "a")?.isCompleted == false)
        #expect(vm.toast?.message.text == "Không lưu được vào Lời nhắc. Bạn thử lại nhé.")
        #expect(vm.toast?.undo == nil)
        #expect(vm.sections[0].rows.map(\.id) == ["a"])
    }

    @Test func permissionStepZero() async {
        let ask = MockPermissionManager([.reminders: .notDetermined])
        let vm = model(ask)
        await vm.load()
        #expect(vm.pendingPermission == PendingPermission(capability: .reminders, variant: .explainer))
        #expect(ask.requested.isEmpty && vm.sections.isEmpty)
        await vm.allowPermission()
        #expect(vm.sections.count == 2)
        let denied = model(MockPermissionManager([.reminders: .denied]))
        await denied.load()
        #expect(denied.pendingPermission?.variant == .denied && denied.isEmpty)
    }

    @Test func emptyAndAdd() async throws {
        let vm = RemindersViewModel(reminders: MockRemindersService(), permissions: permissions, repository: repo,
                                    engine: engine, now: { Self.now }, timeZone: Self.tz)
        await vm.load()
        #expect(vm.isEmpty)
        vm.addReminder()
        let draft = try #require(vm.newDraftId.flatMap(repo.draft))
        #expect(draft.inputMode == .text && draft.originalInput.isEmpty && draft.steps.isEmpty)
    }

    @Test func s12StringsExist() {
        for key in ["reminders.title", "reminders.overdue", "reminders.upcoming", "reminders.empty", "reminders.add",
                    "reminders.complete.a11y", "reminders.completed.toast", "reminders.snooze", "reminders.snooze.title"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
    }
}

/// 1C.6b — S12 row menu: "Nhắc lại sau" sheet / "Sửa" / "Xóa" → S04 (spec §6.5 AC2–AC3, D-108).
@MainActor
@Suite("S12 row menu → S04")
struct RemindersMenuTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-13T10:00:00+07:00")!

    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()
    let reminders = MockRemindersService([ReminderSummary(id: "a", title: "Uống thuốc", dueDate: now + 3600,
                                                          notes: "Sau ăn", isCompleted: false, isRecurring: false)])
    var engine: TaskEngine {
        TaskEngine(repository: repo,
                   executors: [.reminder: RemindersExecutor(reminders: reminders, permissions: permissions,
                                                            now: { Self.now }, morningHour: { 7 })],
                   now: { Self.now })
    }

    func model(_ e: TaskEngine) async -> RemindersViewModel {
        let vm = RemindersViewModel(reminders: reminders, permissions: permissions, repository: repo, engine: e,
                                    snoozeMorningHour: 7, now: { Self.now }, timeZone: Self.tz)
        await vm.load()
        return vm
    }

    @Test func snoozeSheetChoiceOpensReviewThenMovesTheDueDate() async throws {
        let e = engine
        let vm = await model(e)
        #expect(RemindersViewModel.snoozeOptions.map(vm.snoozeLabel) == ["15 phút nữa", "1 tiếng nữa", "Sáng mai lúc 7 giờ"])
        vm.startSnooze("a")
        #expect(vm.snoozing?.id == "a")
        vm.snooze("min15")
        #expect(vm.snoozing == nil)
        let draft = try #require(vm.reviewDraftId.flatMap(repo.draft))
        let step = draft.steps[0]
        #expect(step.operation == .snooze && step.targetRef == "a" && step.field("snoozeOption")?.value == "min15")
        #expect(step.state == .awaitingApproval)
        #expect(try await reminders.find(identifier: "a")?.dueDate == Self.now + 3600)   // nothing before "Xác nhận"
        let review = ReviewViewModel(draftId: draft.id, repository: repo, engine: e, permissions: permissions,
                                     snoozeMorningHour: 7)
        await review.confirm()
        #expect(review.step?.state == .succeeded)
        #expect(try await reminders.find(identifier: "a")?.dueDate == Self.now + 15 * 60)  // 10:00 + 15 min
    }

    @Test func editOpensAnUpdateDraftWithTheReminderValues() async throws {
        let vm = await model(engine)
        vm.change("a", .update)
        let step = try #require(vm.reviewDraftId.flatMap(repo.draft)?.steps.first)
        #expect(step.operation == .update && step.targetRef == "a")
        #expect(step.field("title")?.value == "Uống thuốc" && step.field("notes")?.value == "Sau ăn")
        #expect(step.field("dueDate")?.value == "2026-11-13T11:00:00+07:00")
        #expect(step.field("title")?.source == .device(origin: "reminders"))
        #expect(reminders.saveCount == 0)
    }

    @Test func deleteGoesThroughReview() async throws {
        let e = engine
        let vm = await model(e)
        vm.change("a", .delete)
        let draft = try #require(vm.reviewDraftId.flatMap(repo.draft))
        let review = ReviewViewModel(draftId: draft.id, repository: repo, engine: e, permissions: permissions)
        #expect(review.isDelete && review.blocker == nil)                           // "Xác nhận xóa" (D-108)
        #expect(reminders.deleted.isEmpty)
        await review.confirm()
        #expect(reminders.deleted == ["a"])
        await vm.load()
        #expect(vm.isEmpty)
    }
}
