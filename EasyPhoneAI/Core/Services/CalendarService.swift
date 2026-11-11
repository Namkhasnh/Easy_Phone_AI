import Foundation

/// One calendar event as the app sees it (ARCHITECTURE §4.2). 🔒 `id` / `calendarId` never leave the device (D-056).
// TODO(spec): ARCHITECTURE §4.2 names `EventSummary` / `EventInput` but gives no fields; these follow the
// calendarEvent catalog (DATA_MODEL §4) plus what S11 / the conflict card need (calendar name, recurring).
struct EventSummary: Sendable, Hashable, Identifiable {
    /// EventKit `eventIdentifier` (evidence `ek:event:<id>`, DATA_MODEL §3.5).
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    /// First relative alarm, minutes before start (`alertMinutesBefore`).
    var alertMinutesBefore: Int?
    var calendarId: String?
    var calendarName: String?
    /// `easyphone:<stepId>` when the app created it (D-225).
    var stepTag: String?
    /// Recurring events are out of scope to create or edit (spec §6.4 AC5).
    var isRecurring: Bool
}

/// What an executor writes (calendarEvent create / update).
struct EventInput: Sendable, Hashable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var location: String?
    var notes: String?
    var alertMinutesBefore: Int?
    /// nil = the default calendar for new events.
    var calendarId: String?
}

/// `easyphone:<stepId>` stored in the EventKit item `url` for idempotent lookup (D-105, D-225).
enum StepTag {
    static let scheme = "easyphone"

    static func make(_ stepId: UUID) -> String { "\(scheme):\(stepId.uuidString)" }

    /// The tag of an item URL, nil when the URL is not one of ours.
    static func read(_ url: URL?) -> String? {
        guard let url, url.scheme == scheme else { return nil }
        return url.absoluteString
    }
}

/// EventKit calendar (ARCHITECTURE §4.2). Reads need full access → else `ServiceError.permissionDenied(.calendar)`;
/// `save` also works with write-only access (no reads, so no conflict check: `perm.writeOnly.calendar`).
protocol CalendarService: Sendable {
    func events(in range: DateInterval) async throws -> [EventSummary]
    /// Timed events overlapping `[start, end)` (spec §6.4 AC2).
    func conflicts(start: Date, end: Date) async throws -> [EventSummary]
    func find(identifier: String) async throws -> EventSummary?
    func find(stepTag: String) async throws -> EventSummary?
    /// Candidates for `targetRef` (update / delete); closest to `near` first.
    func search(title: String?, near: Date?) async throws -> [EventSummary]
    /// Creates (`existing == nil`) or updates; returns the `eventIdentifier`.
    func save(_ event: EventInput, stepTag: String, existing: String?) async throws -> String
    func delete(identifier: String) async throws
}

extension EventSummary {
    /// Overlap with `[start, end)`; all-day events never count as conflicts.
    // TODO(spec): spec §6.4 AC2 does not say whether all-day events conflict; they are skipped.
    func overlaps(start: Date, end: Date) -> Bool {
        !isAllDay && self.start < end && self.end > start
    }

    /// Title match for `search`: normalized (no diacritics / case, DATA_MODEL §7.2) substring either way.
    func matches(title query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        let q = NameNormalizer.normalize(query), t = NameNormalizer.normalize(title)
        return !q.isEmpty && (t.contains(q) || q.contains(t))
    }
}

enum CalendarSearch {
    /// `search` window around `near` (or from now) and the `find(stepTag:)` window.
    // TODO(spec): no search window in the docs; ±30 days around the date, else the next year;
    // stepTag lookup scans −1 … +3 years (EventKit predicates are capped at 4 years).
    static func window(near: Date?, now: Date) -> DateInterval {
        let day: TimeInterval = 86_400
        if let near { return DateInterval(start: near - 30 * day, end: near + 30 * day) }
        return DateInterval(start: now - day, end: now + 365 * day)
    }

    static func tagWindow(now: Date) -> DateInterval {
        DateInterval(start: now - 365 * 86_400, end: now + 3 * 365 * 86_400)
    }

    /// Closest to `near` first, else by start.
    static func sort(_ events: [EventSummary], near: Date?) -> [EventSummary] {
        guard let near else { return events.sorted { $0.start < $1.start } }
        return events.sorted { abs($0.start.timeIntervalSince(near)) < abs($1.start.timeIntervalSince(near)) }
    }
}

extension CalendarSearch {
    /// Ids of timed events that overlap another timed event of the list (S11 "Trùng giờ", spec §6.4 AC2).
    static func conflictingIds(_ events: [EventSummary]) -> Set<String> {
        var ids = Set<String>()
        for (i, a) in events.enumerated() {
            for b in events[(i + 1)...] where a.overlaps(start: b.start, end: b.end) && !b.isAllDay {
                ids.insert(a.id)
                ids.insert(b.id)
            }
        }
        return ids
    }
}
