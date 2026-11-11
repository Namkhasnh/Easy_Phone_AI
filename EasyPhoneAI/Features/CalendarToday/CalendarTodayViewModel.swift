import Foundation
import Observation

/// S11 Calendar today (UI_SCREENS S11, spec §6.4 AC1). Reading needs full calendar access: step 0 → S18 (D-185).
@Observable @MainActor final class CalendarTodayViewModel {
    struct Row: Identifiable, Hashable {
        let id: String
        let time: String               // "HH:mm" or `calendar.allDay`
        let title: String
        let location: String?
        let conflicts: Bool
    }

    private(set) var rows: [Row] = []
    private(set) var loaded = false
    /// S18 before reading the calendar (explainer / denied).
    var pendingPermission: PendingPermission?
    /// Set by "Thêm lịch hẹn": the View opens S03 in typing mode for this draft.
    private(set) var newDraftId: UUID?
    /// Detail sheet (UI_SCREENS S11): the tapped event.
    var selected: EventSummary?
    /// Set by "Sửa" / "Xóa": the View opens S04 for this new update / delete draft.
    private(set) var reviewDraftId: UUID?
    private var events: [EventSummary] = []

    private let calendar: any CalendarService
    private let permissions: any PermissionManager
    private let repository: any TaskRepository
    private let engine: TaskEngine
    private let now: () -> Date
    private let timeZone: TimeZone

    init(calendar: any CalendarService, permissions: any PermissionManager, repository: any TaskRepository,
         engine: TaskEngine, now: @escaping () -> Date = { .now }, timeZone: TimeZone = .current) {
        self.engine = engine
        self.calendar = calendar
        self.permissions = permissions
        self.repository = repository
        self.now = now
        self.timeZone = timeZone
    }

    var dayText: String { FieldFormatter.day(now(), timeZone: timeZone) }
    var isEmpty: Bool { loaded && rows.isEmpty }

    /// On appear and when the app is active again. Never asks without the explainer (D-185).
    func load() async {
        switch permissions.status(.calendar) {
        case .notDetermined:
            pendingPermission = PendingPermission(capability: .calendar, variant: .explainer)
            return
        case .denied, .restricted, .writeOnly:
            // TODO(spec): S11 has no write-only text; write-only cannot read events, so the denied variant is shown.
            pendingPermission = PendingPermission(capability: .calendar, variant: .denied)
            loaded = true
            return
        case .granted, .limited:
            break
        }
        do {
            let events = try await calendar.events(in: today)
            self.events = events
            let conflicts = CalendarSearch.conflictingIds(events)
            rows = events.map { e in
                Row(id: e.id,
                    time: e.isAllDay ? UserMessage(key: "calendar.allDay").text : FieldFormatter.time(e.start, timeZone: timeZone),
                    title: e.title, location: e.location, conflicts: conflicts.contains(e.id))
            }
        } catch {
            // TODO(spec): S11 has no load-error text; the list stays empty (the empty text is shown).
            rows = []
        }
        loaded = true
    }

    /// S18 "Cho phép" → system alert → read.
    func allowPermission() async {
        guard pendingPermission?.variant == .explainer else { return }
        pendingPermission = nil
        let status = await permissions.request(.calendar)
        if status == .granted || status == .limited {
            await load()
        } else {
            pendingPermission = PendingPermission(capability: .calendar, variant: .denied)
            loaded = true
        }
    }

    func dismissPermission() {
        pendingPermission = nil
        loaded = true
    }

    /// "Thêm lịch hẹn" → S03 in typing mode: an empty typed draft opens as an editable transcript (no auto-send).
    // TODO(spec): `Route.conversation` has no typing-mode flag; an empty `.text` draft gives the same screen.
    func addEvent() {
        let draft = TaskDraft(inputMode: .text, originalInput: "")
        repository.save(draft)
        newDraftId = draft.id
    }

    func didOpenNewDraft() { newDraftId = nil }

    // MARK: - Detail sheet

    func select(_ rowId: String) {
        selected = events.first { $0.id == rowId }
    }

    /// Read-only rows: catalog order, 🔒 / empty values hidden, values formatted like S04 (`FieldFormatter`).
    var detailRows: [(labelKey: String, value: String)] {
        guard let selected else { return [] }
        let tz = timeZone.identifier
        return DraftBuilder.step(from: selected, operation: .update, timeZoneId: tz).fields.compactMap { field in
            guard !field.deviceOnly, field.id != "allDay" || selected.isAllDay,
                  let value = FieldFormatter.display(field, timeZoneId: tz), !value.isEmpty else { return nil }
            return (field.labelKey(kind: .calendarEvent), value)
        }
    }

    /// Recurring → `calendar.recurringUnsupported` instead of "Sửa" / "Xóa" (spec §6.4 AC5).
    var canChangeSelected: Bool { selected.map { !$0.isRecurring } ?? false }

    /// "Sửa" / "Xóa": a new update / delete step → S04. Nothing changes in Calendar before "Xác nhận" (D-100).
    func change(_ operation: TaskOperation) {
        guard let selected, let draft = engine.startDraft(from: selected, operation: operation,
                                                          timeZoneId: timeZone.identifier) else { return }
        self.selected = nil
        reviewDraftId = draft.id
    }

    func didOpenReview() { reviewDraftId = nil }

    /// "Mở trong Lịch" (spec §6.4 AC4): the Calendar app at the event's start.
    // TODO(spec): no doc names the URL; `calshow:<seconds since 2001-01-01>` opens Calendar at that time.
    var openInCalendarURL: URL? {
        selected.flatMap { URL(string: "calshow:\(Int($0.start.timeIntervalSinceReferenceDate))") }
    }

    private var today: DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: now())
        return DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: start) ?? start + 86_400)
    }
}
