import Foundation

/// One reminder as the app sees it (ARCHITECTURE §4.2). 🔒 `id` never leaves the device (D-056).
// TODO(spec): ARCHITECTURE §4.2 names `ReminderSummary` / `ReminderInput` without fields; these follow the reminder
// catalog (DATA_MODEL §4) plus what S12 needs (completed, recurring).
struct ReminderSummary: Sendable, Hashable, Identifiable {
    /// EventKit `calendarItemIdentifier` (evidence `ek:reminder:<id>`, DATA_MODEL §3.5).
    let id: String
    var title: String
    var dueDate: Date?
    var notes: String?
    var isCompleted: Bool
    /// `easyphone:<stepId>` when the app wrote it (D-225).
    var stepTag: String?
    /// Recurring reminders are out of scope (spec §6.5 "one-time reminders").
    var isRecurring: Bool
}

/// What an executor writes (reminder create / update). The alarm is at `dueDate` (spec §6.5 AC1).
struct ReminderInput: Sendable, Hashable {
    var title: String
    var dueDate: Date
    var notes: String?
}

/// EventKit reminders (ARCHITECTURE §4.2). Everything needs full reminders access, else
/// `ServiceError.permissionDenied(.reminders)` (iOS has no write-only access for reminders).
protocol RemindersService: Sendable {
    /// Not completed reminders, for S12 (1C.6), by due date (no due date last).
    // TODO(spec): ARCHITECTURE §4.2 has no list call, but S12 lists "Quá hạn" / "Sắp tới"; added here.
    func incomplete() async throws -> [ReminderSummary]
    func find(identifier: String) async throws -> ReminderSummary?
    func find(stepTag: String) async throws -> ReminderSummary?
    /// Creates (`existing == nil`) or updates; returns the `calendarItemIdentifier`.
    func save(_ reminder: ReminderInput, stepTag: String, existing: String?) async throws -> String
    /// reminder/complete with `completed` (D-248): `false` = "Hoàn tác".
    func setCompleted(_ id: String, _ done: Bool) async throws
    /// Moves the due date and its alarm.
    func snooze(_ id: String, to date: Date) async throws
    func delete(identifier: String) async throws
}

extension ReminderSummary {
    /// S12 order: by due date, reminders without a date last, then by title.
    static func ordered(_ items: [ReminderSummary]) -> [ReminderSummary] {
        items.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.title < b.title
            }
        }
    }
}
