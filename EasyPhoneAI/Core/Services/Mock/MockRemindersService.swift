import Foundation
import Synchronization

/// In-memory `RemindersService` for previews and tests (D-206). Everything needs `.granted` like the live one;
/// ids are `mock-reminder-<n>`. Records calls for idempotency tests.
final class MockRemindersService: RemindersService {
    private struct State {
        var items: [String: ReminderSummary] = [:]
        var access: PermissionStatus
        var nextId = 1
        var saveCount = 0
        var deleted: [String] = []
        var failNext = false
    }

    private let state: Mutex<State>

    init(_ items: [ReminderSummary] = [], access: PermissionStatus = .granted) {
        state = Mutex(State(items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }), access: access))
    }

    var saveCount: Int { state.withLock { $0.saveCount } }
    var deleted: [String] { state.withLock { $0.deleted } }
    var all: [ReminderSummary] { state.withLock { ReminderSummary.ordered(Array($0.items.values)) } }

    func setAccess(_ access: PermissionStatus) { state.withLock { $0.access = access } }
    /// Next write throws `eventkit.saveFailed`.
    func failNextWrite() { state.withLock { $0.failNext = true } }

    func incomplete() async throws -> [ReminderSummary] {
        try read { ReminderSummary.ordered($0.items.values.filter { !$0.isCompleted }) }
    }

    func find(identifier: String) async throws -> ReminderSummary? { try read { $0.items[identifier] } }

    func find(stepTag: String) async throws -> ReminderSummary? {
        try read { $0.items.values.first { $0.stepTag == stepTag } }
    }

    func save(_ input: ReminderInput, stepTag: String, existing: String?) async throws -> String {
        try write { s in
            let id: String
            if let existing {
                guard s.items[existing] != nil else { throw ServiceError.notFound }
                id = existing
            } else {
                id = "mock-reminder-\(s.nextId)"
                s.nextId += 1
            }
            s.saveCount += 1
            let completed = s.items[id]?.isCompleted ?? false
            s.items[id] = ReminderSummary(id: id, title: input.title, dueDate: input.dueDate, notes: input.notes,
                                          isCompleted: completed, stepTag: stepTag, isRecurring: false)
            return id
        }
    }

    func setCompleted(_ id: String, _ done: Bool) async throws {
        try write { s in
            guard s.items[id] != nil else { throw ServiceError.notFound }
            s.items[id]?.isCompleted = done
        }
    }

    func snooze(_ id: String, to date: Date) async throws {
        try write { s in
            guard s.items[id] != nil else { throw ServiceError.notFound }
            s.items[id]?.dueDate = date
        }
    }

    func delete(identifier: String) async throws {
        try write { s in
            guard s.items.removeValue(forKey: identifier) != nil else { throw ServiceError.notFound }
            s.deleted.append(identifier)
        }
    }

    private func read<T>(_ body: (State) throws -> T) throws -> T {
        try state.withLock { s in
            guard s.access == .granted else { throw ServiceError.permissionDenied(.reminders) }
            return try body(s)
        }
    }

    private func write<T>(_ body: (inout State) throws -> T) throws -> T {
        try state.withLock { s in
            guard s.access == .granted else { throw ServiceError.permissionDenied(.reminders) }
            if s.failNext {
                s.failNext = false
                throw ServiceError.framework(code: "eventkit.saveFailed")
            }
            return try body(&s)
        }
    }
}
