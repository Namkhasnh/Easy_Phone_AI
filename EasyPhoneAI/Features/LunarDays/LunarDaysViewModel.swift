import Foundation
import Observation

/// S22 "Ngày giỗ & lễ" (4L.6, D-331; UI_SCREENS_P4 S22): today's lunar date, the lunar series the user saved (giỗ,
/// mùng 1 / rằm…) and the main lunar holidays, each with its next solar date and the days left. Read-only.
@Observable @MainActor final class LunarDaysViewModel {
    struct Row: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        /// "10/3 âm lịch", "Ngày 1 hằng tháng (âm lịch) lúc 06:00".
        let lunarLabel: String
        /// "Thứ Sáu, 16/4/2027 · còn 144 ngày" / "… · hôm nay".
        let nextLabel: String
        let daysLeft: Int
    }

    /// The fixed lunar holidays (day, month).
    // TODO(spec): D-331 names no holiday list; the common Vietnamese ones are used.
    enum Holiday: String, CaseIterable, Sendable {
        case tet, ramGieng, gioTo, phatDan, doanNgo, vuLan, trungThu, ongTao
        var date: (month: Int, day: Int) {
            switch self {
            case .tet: (1, 1)
            case .ramGieng: (1, 15)
            case .gioTo: (3, 10)
            case .phatDan: (4, 15)
            case .doanNgo: (5, 5)
            case .vuLan: (7, 15)
            case .trungThu: (8, 15)
            case .ongTao: (12, 23)
            }
        }
        var titleKey: String { "lunarDays.holiday.\(rawValue)" }
    }

    private(set) var todayLine = ""
    private(set) var saved: [Row] = []
    private(set) var holidays: [Row] = []
    private(set) var loaded = false

    private let repository: any TaskRepository
    private let calendar: any CalendarService
    private let reminders: any RemindersService
    private let permissions: any PermissionManager
    private let now: @MainActor () -> Date

    init(repository: any TaskRepository, calendar: any CalendarService, reminders: any RemindersService,
         permissions: any PermissionManager, now: @escaping @MainActor () -> Date = { .now }) {
        self.repository = repository
        self.calendar = calendar
        self.reminders = reminders
        self.permissions = permissions
        self.now = now
    }

    func load() async {
        let now = now()
        todayLine = LunarQuestion.today.answer(now: now)
        holidays = Holiday.allCases.compactMap { h in
            row(id: h.rawValue, title: UserMessage(key: h.titleKey).text,
                value: String(format: "%02d-%02d", h.date.month, h.date.day), recurrence: .yearly, now: now)
        }.sorted { $0.daysLeft < $1.daysLeft }
        var rows: [Row] = []
        let open = permissions.status(.reminders) == .granted ? (try? await reminders.incomplete()) : nil
        for (_, step) in repository.steps(in: [.succeeded]) {
            guard let recurrence = LunarSeries.recurrence(of: step), let raw = step.field("lunarDate")?.value,
                  let title = step.field("title")?.value,
                  let row = row(id: step.id.uuidString, title: title, value: raw, recurrence: recurrence, now: now)
            else { continue }
            guard await stillThere(step, open: open, nextIn: row.daysLeft, now: now) else { continue }
            rows.append(row)
        }
        saved = rows.sorted { $0.daysLeft < $1.daysLeft }
        loaded = true
    }

    /// A series the user deleted (here or in Lịch / Lời nhắc) is not listed. Without full access it is listed.
    private func stillThere(_ step: TaskStep, open: [ReminderSummary]?, nextIn days: Int, now: Date) async -> Bool {
        let base = StepTag.make(step.id)
        switch step.kind {
        case .calendarEvent:
            guard permissions.status(.calendar) == .granted else { return true }
            let next = now + TimeInterval(days) * 86_400
            guard let events = try? await calendar.events(in: CalendarSearch.around(next)) else { return true }
            return events.contains { $0.stepTag.map(StepTag.base) == base }
        case .reminder:
            guard let open else { return true }
            return open.contains { $0.stepTag.map(StepTag.base) == base }
        default:
            return false
        }
    }

    private func row(id: String, title: String, value: String, recurrence: LunarResolver.Recurrence,
                     now: Date) -> Row? {
        guard let v = LunarFieldValue(value) else { return nil }
        let occurrence: LunarResolver.Occurrence
        switch LunarResolver.resolve(v, recurrence: recurrence, now: now) {
        case .date(let o): occurrence = o
        case .choose(let options): guard let o = options.first else { return nil }; occurrence = o
        case .none: return nil
        }
        let days = LunarCalendar.julianDay(occurrence.solar) - LunarCalendar.julianDay(LunarCalendar.solarDay(of: now))
        let solar = LunarQuestion.solarName(occurrence.solar)
        let next = days == 0 ? UserMessage(key: "lunarDays.next.today", args: [solar]).text
                             : UserMessage(key: "lunarDays.next", args: [solar, String(days)]).text
        return Row(id: id, title: title, lunarLabel: FieldFormatter.lunarDate(v), nextLabel: next, daysLeft: days)
    }
}
