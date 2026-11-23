import Foundation

/// 4L.4 (D-331, D-332): turns a `lunarDate` value into the **first** solar date (`startDate` / `dueDate`), on the phone.
/// Pure. The yearly / monthly series beyond the first date is created by the executors (4L.5).
enum LunarResolver {
    enum Recurrence: String, Sendable { case none, yearly, monthly }

    struct Occurrence: Equatable, Sendable {
        var lunar: LunarDate
        var solar: SolarDay
        /// Day 30 asked in a 29-day month → 29 (D-331); the UI says so.
        var adjustedDay: Bool
    }

    enum Result: Equatable, Sendable {
        case date(Occurrence)
        /// D-331: a yearly date said in a leap month → the user picks (regular month every year, or the leap month).
        case choose([Occurrence])
        /// The date does not exist (a leap month that never comes in range, a named lunar year in the past…).
        case none
    }

    /// `today` = the Vietnamese wall-clock day of `now`. Occurrences before today are skipped, except an explicit
    /// lunar year / "tháng này" (N0), which keep the date the user said.
    static func resolve(_ v: LunarFieldValue, recurrence: Recurrence, now: Date) -> Result {
        let todaySolar = LunarCalendar.solarDay(of: now)
        let today = LunarCalendar.lunar(from: todaySolar)

        func occurrence(day: Int, month: Int, year: Int, leap: Bool) -> Occurrence? {
            guard let length = LunarCalendar.monthLength(month: month, year: year, isLeap: leap) else { return nil }
            let used = min(day, length)
            let lunar = LunarDate(day: used, month: month, year: year, isLeap: leap)
            guard let solar = LunarCalendar.solar(from: lunar) else { return nil }
            return Occurrence(lunar: lunar, solar: solar, adjustedDay: used != day)
        }
        // Today counts unless the said hour has already passed (Vietnamese wall clock).
        var vn = Calendar(identifier: .gregorian)
        vn.timeZone = LunarCalendar.vietnamTimeZone
        let nowMinutes = vn.component(.hour, from: now) * 60 + vn.component(.minute, from: now)
        let todayPassed = v.hour.map { $0 * 60 + (v.minute ?? 0) <= nowMinutes } ?? false
        func upcoming(_ o: Occurrence?) -> Occurrence? {
            o.flatMap { $0.solar > todaySolar || ($0.solar == todaySolar && !todayPassed) ? $0 : nil }
        }
        /// The month `offset` months after today's, then that day (leap months count, `LunarQuestion.month`).
        func inMonth(offset: Int) -> Occurrence? {
            LunarQuestion.month(after: today, offset: offset).flatMap {
                occurrence(day: v.day, month: $0.month, year: $0.year, leap: $0.isLeap)
            }
        }

        switch v.monthToken {
        case .thisMonth:
            return inMonth(offset: 0).map(Result.date) ?? .none
        case .nextMonth:
            return inMonth(offset: 1).map(Result.date) ?? .none
        case .nextOccurrence, .number(0):
            // "rằm", "mùng 5 âm lịch", every month: this lunar month if the day is still ahead, else the next one.
            return (upcoming(inMonth(offset: 0)) ?? inMonth(offset: 1)).map(Result.date) ?? .none
        case .number(let month):
            if let year = v.year {
                return occurrence(day: v.day, month: month, year: year, leap: v.isLeap).map(Result.date) ?? .none
            }
            let regular = (today.year...today.year + 1).lazy
                .compactMap { upcoming(occurrence(day: v.day, month: month, year: $0, leap: false)) }.first
            guard v.isLeap else { return regular.map(Result.date) ?? .none }
            // The leap month: the next lunar year (within ~20) that has it.
            let leap = (today.year...today.year + 20).lazy
                .compactMap { upcoming(occurrence(day: v.day, month: month, year: $0, leap: true)) }.first
            switch (recurrence, leap, regular) {
            case (.yearly, let l?, let r?): return .choose([r, l])     // D-331: ask, never pick
            case (_, let l?, _): return .date(l)
            case (.yearly, nil, let r?): return .date(r)
            default: return .none
            }
        }
    }

    /// The `dateTime` value: the solar day at the said hour, else `defaultHour` (reminders) / 00:00 (all-day events).
    static func dateTime(_ o: Occurrence, hour: Int?, minute: Int?, defaultHour: Int, timeZone: TimeZone) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: o.solar.year, month: o.solar.month, day: o.solar.day,
                                                            hour: hour ?? defaultHour, minute: minute ?? 0)) else { return nil }
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
