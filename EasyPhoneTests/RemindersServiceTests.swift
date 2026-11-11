import EventKit
import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.5a — ARCHITECTURE §4.2, spec §6.5 AC1, D-225, D-248.
@Suite("RemindersService (EventKit)")
struct RemindersServiceTests {
    static let due = Validator.parseDateTime("2026-11-13T08:00:00+07:00")!

    @Test func applyAndSummaryRoundTrip() throws {
        let reminder = EKReminder(eventStore: EKEventStore())
        let tag = StepTag.make(UUID())
        LiveRemindersService.apply(ReminderInput(title: "Uống thuốc", dueDate: Self.due, notes: "Sau bữa sáng"),
                                   stepTag: tag, to: reminder)
        let s = LiveRemindersService.summary(reminder)
        #expect(s.title == "Uống thuốc" && s.notes == "Sau bữa sáng" && !s.isCompleted && !s.isRecurring)
        #expect(s.dueDate == Self.due)
        #expect(s.stepTag == tag)                                              // D-225
        let alarm = try #require(reminder.alarms?.first)
        #expect(alarm.absoluteDate == Self.due)                                // AC1: alarm at the due date
        LiveRemindersService.setDue(Self.due + 3600, on: reminder)              // snooze moves date + alarm
        #expect(LiveRemindersService.summary(reminder).dueDate == Self.due + 3600)
        #expect(reminder.alarms?.count == 1 && reminder.alarms?.first?.absoluteDate == Self.due + 3600)
    }

    @Test func orderingPutsUndatedLast() {
        func r(_ id: String, _ due: Date?) -> ReminderSummary {
            ReminderSummary(id: id, title: id, dueDate: due, isCompleted: false, isRecurring: false)
        }
        let ordered = ReminderSummary.ordered([r("none", nil), r("late", Self.due + 60), r("early", Self.due)])
        #expect(ordered.map(\.id) == ["early", "late", "none"])
    }

    @Test func mockLifecycle() async throws {
        let svc = MockRemindersService()
        let tag = StepTag.make(UUID())
        let id = try await svc.save(ReminderInput(title: "Uống thuốc", dueDate: Self.due), stepTag: tag, existing: nil)
        #expect(try await svc.find(stepTag: tag)?.id == id)
        try await svc.setCompleted(id, true)
        #expect(try await svc.incomplete().isEmpty)
        #expect(try await svc.find(stepTag: tag)?.isCompleted == true)          // completed still found by tag
        try await svc.setCompleted(id, false)                                   // "Hoàn tác" (D-248)
        try await svc.snooze(id, to: Self.due + 900)
        #expect(try await svc.find(identifier: id)?.dueDate == Self.due + 900)
        try await svc.delete(identifier: id)
        await #expect(throws: ServiceError.notFound) { try await svc.setCompleted(id, true) }
    }

    @Test(arguments: [PermissionStatus.denied, .notDetermined, .writeOnly])
    func mockNeedsFullAccess(_ access: PermissionStatus) async {
        let svc = MockRemindersService(access: access)
        await #expect(throws: ServiceError.permissionDenied(.reminders)) { _ = try await svc.incomplete() }
        await #expect(throws: ServiceError.permissionDenied(.reminders)) {
            _ = try await svc.save(ReminderInput(title: "x", dueDate: Self.due), stepTag: "easyphone:x", existing: nil)
        }
    }

    @Test func liveWithoutAccessThrowsPermissionDenied() async {
        guard EKEventStore.authorizationStatus(for: .reminder) != .fullAccess else { return }
        await #expect(throws: ServiceError.permissionDenied(.reminders)) { _ = try await LiveRemindersService().incomplete() }
    }
}
