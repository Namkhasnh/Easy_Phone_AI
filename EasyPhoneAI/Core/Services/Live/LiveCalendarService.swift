import EventKit
import Foundation
import OSLog

/// EventKit events (ARCHITECTURE §4.2, spec §6.4). An actor: `EKEventStore` / `EKEvent` are not `Sendable`, so they
/// never leave this isolation; callers get value types only. Only error codes are logged, never event content (D-059).
actor LiveCalendarService: CalendarService {
    private var store = EKEventStore()
    private var storeStatus: EKAuthorizationStatus?
    private let now: @Sendable () -> Date
    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "calendar")

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
    }

    // MARK: - Reads (full access)

    func events(in range: DateInterval) async throws -> [EventSummary] {
        let store = try readableStore()
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        return store.events(matching: predicate).map(Self.summary).sorted { $0.start < $1.start }
    }

    func conflicts(start: Date, end: Date) async throws -> [EventSummary] {
        try await events(in: DateInterval(start: start, end: max(start, end)))
            .filter { $0.overlaps(start: start, end: end) }
    }

    func find(identifier: String) async throws -> EventSummary? {
        try readableStore().event(withIdentifier: identifier).map(Self.summary)
    }

    func find(stepTag: String) async throws -> EventSummary? {
        try await events(in: CalendarSearch.tagWindow(now: now())).first { $0.stepTag == stepTag }
    }

    func search(title: String?, near: Date?) async throws -> [EventSummary] {
        let found = try await events(in: CalendarSearch.window(near: near, now: now()))
            .filter { !$0.isRecurring && $0.matches(title: title) }   // recurring: out of scope (spec §6.4 AC5)
        return CalendarSearch.sort(found, near: near)
    }

    // MARK: - Writes (full or write-only access)

    func save(_ input: EventInput, stepTag: String, existing: String?) async throws -> String {
        let store = try writableStore()
        let event: EKEvent
        if let existing {
            guard let found = store.event(withIdentifier: existing) else { throw ServiceError.notFound }
            event = found
        } else {
            event = EKEvent(eventStore: store)
        }
        Self.apply(input, stepTag: stepTag, to: event)
        if let id = input.calendarId, let calendar = store.calendar(withIdentifier: id) {
            event.calendar = calendar
        } else if event.calendar == nil {
            event.calendar = store.defaultCalendarForNewEvents
        }
        guard event.calendar != nil else { throw ServiceError.framework(code: "eventkit.saveFailed") }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            Self.logger.error("calendar save failed: \((error as NSError).code, privacy: .public)")
            throw ServiceError.framework(code: "eventkit.saveFailed")
        }
        guard let id = event.eventIdentifier else { throw ServiceError.framework(code: "eventkit.saveFailed") }
        return id
    }

    func delete(identifier: String) async throws {
        let store = try writableStore()
        guard let event = store.event(withIdentifier: identifier) else { throw ServiceError.notFound }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            Self.logger.error("calendar delete failed: \((error as NSError).code, privacy: .public)")
            // TODO(spec): UI_SCREENS §8 has no delete-specific EventKit error; the save text is used.
            throw ServiceError.framework(code: "eventkit.saveFailed")
        }
    }

    // MARK: - Access

    /// A store created before access was granted keeps seeing nothing; recreate it when the status changes.
    private func currentStore() -> EKEventStore {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != storeStatus {
            store = EKEventStore()
            storeStatus = status
        }
        return store
    }

    private func readableStore() throws -> EKEventStore {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw ServiceError.permissionDenied(.calendar)
        }
        return currentStore()
    }

    private func writableStore() throws -> EKEventStore {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: return currentStore()
        default: throw ServiceError.permissionDenied(.calendar)
        }
    }

    // MARK: - Mapping (pure, unit-tested)

    static func summary(_ event: EKEvent) -> EventSummary {
        EventSummary(id: event.eventIdentifier ?? "",
                     title: event.title ?? "",
                     start: event.startDate,
                     end: event.endDate,
                     isAllDay: event.isAllDay,
                     location: event.location?.nilIfEmpty,
                     notes: event.notes?.nilIfEmpty,
                     alertMinutesBefore: event.alarms?.first.map { Int((-$0.relativeOffset / 60).rounded()) },
                     calendarId: event.calendar?.calendarIdentifier,
                     calendarName: event.calendar?.title,
                     stepTag: StepTag.read(event.url),
                     isRecurring: event.hasRecurrenceRules)
    }

    static func apply(_ input: EventInput, stepTag: String, to event: EKEvent) {
        event.title = input.title
        event.startDate = input.start
        event.endDate = input.end
        event.isAllDay = input.isAllDay
        event.location = input.location
        event.notes = input.notes
        event.url = URL(string: stepTag)                          // D-225
        event.alarms = input.alertMinutesBefore.map { [EKAlarm(relativeOffset: TimeInterval(-$0 * 60))] }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
