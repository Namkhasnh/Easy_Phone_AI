import EventKit
import Foundation
import OSLog

/// EventKit reminders (ARCHITECTURE §4.2, spec §6.5). An actor: `EKEventStore` / `EKReminder` are not `Sendable` and
/// never leave this isolation (the fetch callback maps to values before resuming). Only error codes are logged (D-059).
actor LiveRemindersService: RemindersService {
    private var store = EKEventStore()
    private var storeStatus: EKAuthorizationStatus?
    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "reminders")

    // MARK: - Reads

    func incomplete() async throws -> [ReminderSummary] {
        let store = try usableStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return ReminderSummary.ordered(await fetch(predicate, in: store))
    }

    func find(identifier: String) async throws -> ReminderSummary? {
        (try usableStore().calendarItem(withIdentifier: identifier) as? EKReminder).map(Self.summary)
    }

    func find(stepTag: String) async throws -> ReminderSummary? {
        let store = try usableStore()
        // Completed ones too: a lost result of "complete" must still be found (D-105).
        return await fetch(store.predicateForReminders(in: nil), in: store).first { $0.stepTag == stepTag }
    }

    // MARK: - Writes

    func save(_ input: ReminderInput, stepTag: String, existing: String?) async throws -> String {
        let store = try usableStore()
        let reminder: EKReminder
        if let existing {
            guard let found = store.calendarItem(withIdentifier: existing) as? EKReminder else { throw ServiceError.notFound }
            reminder = found
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = store.defaultCalendarForNewReminders()
        }
        guard reminder.calendar != nil else { throw ServiceError.framework(code: "eventkit.saveFailed") }
        Self.apply(input, stepTag: stepTag, to: reminder)
        try commit(reminder, in: store)
        return reminder.calendarItemIdentifier
    }

    func setCompleted(_ id: String, _ done: Bool) async throws {
        let store = try usableStore()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw ServiceError.notFound }
        reminder.isCompleted = done
        try commit(reminder, in: store)
    }

    func snooze(_ id: String, to date: Date) async throws {
        let store = try usableStore()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw ServiceError.notFound }
        Self.setDue(date, on: reminder)
        try commit(reminder, in: store)
    }

    func delete(identifier: String) async throws {
        let store = try usableStore()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ServiceError.notFound
        }
        do {
            try store.remove(reminder, commit: true)
        } catch {
            Self.logger.error("reminder delete failed: \((error as NSError).code, privacy: .public)")
            throw ServiceError.framework(code: "eventkit.saveFailed")
        }
    }

    // MARK: - Access + EventKit plumbing

    private func usableStore() throws -> EKEventStore {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else { throw ServiceError.permissionDenied(.reminders) }
        if status != storeStatus {                 // a store made before access was granted sees nothing
            store = EKEventStore()
            storeStatus = status
        }
        return store
    }

    private func commit(_ reminder: EKReminder, in store: EKEventStore) throws {
        do {
            try store.save(reminder, commit: true)
        } catch {
            Self.logger.error("reminder save failed: \((error as NSError).code, privacy: .public)")
            throw ServiceError.framework(code: "eventkit.saveFailed")
        }
    }

    private func fetch(_ predicate: NSPredicate, in store: EKEventStore) async -> [ReminderSummary] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.summary))
            }
        }
    }

    // MARK: - Mapping (pure, unit-tested)

    nonisolated static func summary(_ reminder: EKReminder) -> ReminderSummary {
        ReminderSummary(id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        dueDate: reminder.dueDateComponents.flatMap(date(from:)),
                        notes: (reminder.notes?.isEmpty ?? true) ? nil : reminder.notes,
                        isCompleted: reminder.isCompleted,
                        stepTag: StepTag.read(reminder.url),
                        isRecurring: reminder.hasRecurrenceRules)
    }

    static func apply(_ input: ReminderInput, stepTag: String, to reminder: EKReminder) {
        reminder.title = input.title
        reminder.notes = input.notes
        reminder.url = URL(string: stepTag)                        // D-225
        setDue(input.dueDate, on: reminder)
    }

    /// Due date (with its time zone) + one alarm at that moment (spec §6.5 AC1).
    static func setDue(_ date: Date, on reminder: EKReminder) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.timeZone = .current
        reminder.dueDateComponents = components
        reminder.alarms = [EKAlarm(absoluteDate: date)]
    }

    nonisolated static func date(from components: DateComponents) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? .current
        return calendar.date(from: components)
    }
}
