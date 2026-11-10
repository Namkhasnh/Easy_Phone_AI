import Foundation
import Synchronization

/// In-memory `CalendarService` for previews and tests (D-206). Same rules as the live one: reads need `.granted`,
/// writes also accept `.writeOnly`; ids are `mock-event-<n>`. Records saves / deletes for idempotency tests.
final class MockCalendarService: CalendarService {
    private struct State {
        var events: [String: EventSummary] = [:]
        var access: PermissionStatus
        var nextId = 1
        var saveCount = 0
        var deleted: [String] = []
        var failSave = false
    }

    private let state: Mutex<State>

    init(_ events: [EventSummary] = [], access: PermissionStatus = .granted) {
        state = Mutex(State(events: Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) }), access: access))
    }

    var saveCount: Int { state.withLock { $0.saveCount } }
    var deleted: [String] { state.withLock { $0.deleted } }
    var all: [EventSummary] { state.withLock { $0.events.values.sorted { $0.start < $1.start } } }

    func setAccess(_ access: PermissionStatus) { state.withLock { $0.access = access } }
    /// Next `save` throws `eventkit.saveFailed`.
    func failNextSave() { state.withLock { $0.failSave = true } }

    func events(in range: DateInterval) async throws -> [EventSummary] {
        try state.withLock { s in
            guard s.access == .granted else { throw ServiceError.permissionDenied(.calendar) }
            return s.events.values.filter { $0.start < range.end && $0.end > range.start }.sorted { $0.start < $1.start }
        }
    }

    func conflicts(start: Date, end: Date) async throws -> [EventSummary] {
        try await events(in: DateInterval(start: start, end: max(start, end))).filter { $0.overlaps(start: start, end: end) }
    }

    func find(identifier: String) async throws -> EventSummary? {
        try state.withLock { s in
            guard s.access == .granted else { throw ServiceError.permissionDenied(.calendar) }
            return s.events[identifier]
        }
    }

    func find(stepTag: String) async throws -> EventSummary? {
        try await events(in: CalendarSearch.tagWindow(now: .now)).first { $0.stepTag == stepTag }
    }

    func search(title: String?, near: Date?) async throws -> [EventSummary] {
        let found = try await events(in: CalendarSearch.window(near: near, now: .now))
            .filter { !$0.isRecurring && $0.matches(title: title) }
        return CalendarSearch.sort(found, near: near)
    }

    func save(_ input: EventInput, stepTag: String, existing: String?) async throws -> String {
        try state.withLock { s in
            guard s.access == .granted || s.access == .writeOnly else { throw ServiceError.permissionDenied(.calendar) }
            if s.failSave {
                s.failSave = false
                throw ServiceError.framework(code: "eventkit.saveFailed")
            }
            let id: String
            if let existing {
                guard s.events[existing] != nil else { throw ServiceError.notFound }
                id = existing
            } else {
                id = "mock-event-\(s.nextId)"
                s.nextId += 1
            }
            s.saveCount += 1
            s.events[id] = EventSummary(id: id, title: input.title, start: input.start, end: input.end,
                                        isAllDay: input.isAllDay, location: input.location, notes: input.notes,
                                        alertMinutesBefore: input.alertMinutesBefore,
                                        calendarId: input.calendarId ?? "mock-calendar", calendarName: "Lịch",
                                        stepTag: stepTag, isRecurring: false)
            return id
        }
    }

    func delete(identifier: String) async throws {
        try state.withLock { s in
            guard s.access == .granted || s.access == .writeOnly else { throw ServiceError.permissionDenied(.calendar) }
            guard s.events.removeValue(forKey: identifier) != nil else { throw ServiceError.notFound }
            s.deleted.append(identifier)
        }
    }
}
