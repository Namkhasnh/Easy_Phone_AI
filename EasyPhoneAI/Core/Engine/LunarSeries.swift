import Foundation

/// 4L.5 (D-331): the occurrences **after** the first of a lunar yearly / monthly step. EventKit has no lunar rule, so
/// the executors write one item per occurrence, each tagged `easyphone:<stepId>:<suffix>` (D-105, D-225).
/// Yearly: the next 4 lunar years (5 in all), always the regular month, day 30 → 29 when that month has 29 days.
/// Monthly: the next 11 lunar months (12 in all; a leap month counts as a month).
enum LunarSeries {
    static let yearlyCount = 5
    static let monthlyCount = 12

    struct Item: Equatable, Sendable {
        /// `<lunarYear>` (yearly) or `<lunarYear>-<month>[L]` (monthly).
        var suffix: String
        var start: Date
    }

    /// yearly / monthly of a lunar create step; nil for a non-lunar or one-time step.
    static func recurrence(of step: TaskStep) -> LunarResolver.Recurrence? {
        guard step.operation == .create, let raw = step.field("lunarDate")?.value, let v = LunarFieldValue(raw),
              let r = step.field("lunarRecurrence")?.value.flatMap(LunarResolver.Recurrence.init(rawValue:))
                ?? (v.isEveryMonth ? .monthly : nil), r != .none else { return nil }
        return r
    }

    /// Occurrences 2 … `count` (default: one block, 5 years / 12 months). Empty for a non-lunar or one-time step,
    /// or when the first date is missing.
    static func following(_ step: TaskStep, timeZoneId: String, count: Int? = nil) -> [Item] {
        let dateId = step.kind == .calendarEvent ? "startDate" : "dueDate"
        guard let recurrence = recurrence(of: step),
              let v = step.field("lunarDate")?.value.flatMap(LunarFieldValue.init),
              let first = step.field(dateId)?.value.flatMap(Validator.parseDateTime)
        else { return [] }
        let tz = TimeZone(identifier: timeZoneId) ?? LunarCalendar.vietnamTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: first)
        guard let y = c.year, let m = c.month, let d = c.day else { return [] }
        let firstLunar = LunarCalendar.lunar(from: SolarDay(day: d, month: m, year: y))

        func at(_ s: SolarDay) -> Date? {
            calendar.date(from: DateComponents(year: s.year, month: s.month, day: s.day, hour: c.hour, minute: c.minute))
        }
        switch recurrence {
        case .yearly:
            return (1..<(count ?? yearlyCount)).compactMap { i in
                let year = firstLunar.year + i
                guard let a = LunarCalendar.yearlyAnniversary(day: v.day, month: firstLunar.month, inLunarYear: year),
                      let start = at(a.solar) else { return nil }
                return Item(suffix: String(year), start: start)
            }
        case .monthly:
            return (1..<(count ?? monthlyCount)).compactMap { i in
                guard let month = LunarQuestion.month(after: firstLunar, offset: i),
                      let length = LunarCalendar.monthLength(month: month.month, year: month.year, isLeap: month.isLeap),
                      let solar = LunarCalendar.solar(from: LunarDate(day: min(v.day, length), month: month.month,
                                                                      year: month.year, isLeap: month.isLeap)),
                      let start = at(solar) else { return nil }
                return Item(suffix: "\(month.year)-\(month.month)\(month.isLeap ? "L" : "")", start: start)
            }
        case .none:
            return []
        }
    }

    /// 4L.6 (D-331): what launch should add. A series is written in blocks (5 years / 12 months); when fewer than 2
    /// occurrences are still ahead of `now`, the next block(s) are due. `ends` = the last occurrence of each block
    /// already due before (newest first): the extender writes after the newest one it still finds, and nothing when
    /// none is left (the user deleted the series). Nil = nothing to add.
    struct Extension: Equatable, Sendable {
        var ends: [Item]
        /// Every occurrence after the first block, up to the new horizon (looked up before writing, D-105).
        var items: [Item]
    }

    static let minimumAhead = 2

    static func extensionPlan(_ step: TaskStep, timeZoneId: String, now: Date) -> Extension? {
        guard let recurrence = recurrence(of: step) else { return nil }
        let block = recurrence == .yearly ? yearlyCount : monthlyCount
        var blocks = 1
        var items = following(step, timeZoneId: timeZoneId, count: block)
        while items.filter({ $0.start > now }).count < minimumAhead, blocks < 40 {
            blocks += 1
            items = following(step, timeZoneId: timeZoneId, count: blocks * block)
        }
        guard blocks > 1 else { return nil }
        // Occurrence n is items[n - 2] (items start at the 2nd).
        let ends = (1..<blocks).reversed().compactMap { b in items.indices.contains(b * block - 2) ? items[b * block - 2] : nil }
        return Extension(ends: ends, items: Array(items.dropFirst(block - 1)))
    }

    static func tag(_ stepId: UUID, _ suffix: String) -> String { "\(StepTag.make(stepId)):\(suffix)" }

    /// D-331 alarms of a lunar all-day event: 08:00 the day before + 07:00 that day (minutes before 00:00 start).
    // TODO(spec): D-331 wording "Mai giỗ ông, chuẩn bị mâm cỗ" cannot be set: EventKit alarms show the event title.
    static let allDayAlerts = [16 * 60, -7 * 60]
}
