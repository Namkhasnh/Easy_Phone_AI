import Foundation

/// 4L.2 (D-330): lunar-calendar questions answered on the phone — no `/v1/parse`, no unit, works offline.
/// Only questions; anything that creates or changes something ("nhắc", "đặt", "tạo"…) or names another lunar month
/// ("rằm tháng 8") returns nil and goes to the AI as before.
enum LunarQuestion: Equatable, Sendable {
    /// "hôm nay âm lịch ngày mấy"
    case today
    /// "rằm tháng này / tháng sau ngày nào" — lunar day 15 of the current (0) or next (1) lunar month.
    case fullMoon(monthOffset: Int)
    /// "mùng 1 tháng này / tháng sau ngày nào"
    case firstDay(monthOffset: Int)
    /// "Tết còn mấy ngày", "bao giờ Tết"
    case tet

    // MARK: - Matching

    static func match(_ words: LocalIntent.Words) -> LunarQuestion? {
        guard (2...12).contains(words.folded.count) else { return nil }
        let t = " " + words.joined + " "
        guard !actions.contains(where: t.contains) else { return nil }
        let asks = cues.contains(where: t.contains)
        let offset = nextMonth.contains(where: t.contains) ? 1 : 0
        let otherMonth = t.range(of: #" thang (\d+|gieng|chap|mot|hai|ba|bon|nam|sau|bay|tam|chin|muoi) "#,
                                 options: .regularExpression) != nil && !nextMonth.contains(where: t.contains)
        if t.contains(" ram ") {
            guard asks, !otherMonth else { return nil }
            return .fullMoon(monthOffset: offset)
        }
        if t.contains(" tet ") {                                        // "mùng 1 Tết" is Tết, not a month start
            guard asks || t.contains(" con "), !otherMonth else { return nil }
            return .tet
        }
        if t.contains(" mung 1 ") || t.contains(" mung mot ") {
            guard asks, !otherMonth else { return nil }
            return .firstDay(monthOffset: offset)
        }
        if lunarWords.contains(where: t.contains) {
            guard asks || t.contains(" hom nay "), !otherDay.contains(where: t.contains) else { return nil }
            return .today
        }
        return nil
    }

    // Folded by `NameNormalizer` (diacritics removed).
    private static let actions = [" nhac ", " dat ", " tao ", " them ", " ghi ", " hen ", " xoa ", " sua ", " doi ",
                                  " len lich ", " bao thuc ", " goi ", " nhan "]
    private static let cues = [" may ", " nao ", " bao nhieu ", " bao gio ", " khi nao ", " gi ", " chua ", " thu may "]
    private static let nextMonth = [" thang sau ", " thang toi "]
    private static let lunarWords = [" am lich ", " ngay am ", " lich am "]
    private static let otherDay = [" mai ", " ngay kia ", " hom qua ", " hom kia ", " tuan ", " nam sau "]

    // MARK: - Answer

    /// The sentence Khoai shows and reads (string keys from `Localizable.xcstrings`, UI_SCREENS S03 mode 6).
    func answer(now: Date) -> String {
        let todaySolar = LunarCalendar.solarDay(of: now)
        let today = LunarCalendar.lunar(from: todaySolar)
        switch self {
        case .today:
            return UserMessage(key: "lunar.answer.today",
                               args: [Self.dayName(today.day), Self.monthName(today), Self.yearName(today.year)]).text
        case .fullMoon(let offset), .firstDay(let offset):
            let day = self == .fullMoon(monthOffset: offset) ? 15 : 1
            guard let month = Self.month(after: today, offset: offset),
                  let solar = LunarCalendar.solar(from: LunarDate(day: day, month: month.month, year: month.year,
                                                                  isLeap: month.isLeap))
            else { return UserMessage(key: "conv.parseFailed").text }
            return UserMessage(key: "lunar.answer.day",
                               args: [UserMessage(key: day == 15 ? "lunar.day.ram" : "lunar.day.first").text,
                                      Self.monthName(month), Self.solarName(solar)]).text
        case .tet:
            if today.month == 1 && today.day == 1 && !today.isLeap {
                return UserMessage(key: "lunar.answer.tetToday", args: [Self.yearName(today.year)]).text
            }
            let year = today.year + 1
            guard let tet = LunarCalendar.solar(from: LunarDate(day: 1, month: 1, year: year)) else {
                return UserMessage(key: "conv.parseFailed").text
            }
            let days = LunarCalendar.julianDay(tet) - LunarCalendar.julianDay(todaySolar)
            return UserMessage(key: "lunar.answer.tet",
                               args: [String(days), Self.yearName(year), Self.solarName(tet)]).text
        }
    }

    /// The lunar month `offset` months after the one containing `date` (a leap month counts as its own month).
    static func month(after date: LunarDate, offset: Int) -> LunarDate? {
        guard let start = LunarCalendar.solar(from: LunarDate(day: 1, month: date.month, year: date.year,
                                                              isLeap: date.isLeap)) else { return nil }
        var jd = LunarCalendar.julianDay(start)
        var current = LunarCalendar.lunar(from: start)
        for _ in 0..<max(0, offset) {
            guard let length = LunarCalendar.monthLength(month: current.month, year: current.year,
                                                         isLeap: current.isLeap) else { return nil }
            jd += length
            current = LunarCalendar.lunar(from: LunarCalendar.solarDay(julianDay: jd))
        }
        return current
    }

    // MARK: - Names (all from the catalog, D-003)

    /// "mùng 5" for 1…10, else the number.
    static func dayName(_ day: Int) -> String {
        day <= 10 ? UserMessage(key: "lunar.day.mung", args: [String(day)]).text : String(day)
    }

    /// "Giêng", "Chạp", "10", "6 nhuận".
    static func monthName(_ d: LunarDate) -> String {
        let base = switch d.month {
        case 1: UserMessage(key: "lunar.month.first").text
        case 12: UserMessage(key: "lunar.month.last").text
        default: String(d.month)
        }
        return d.isLeap ? UserMessage(key: "lunar.month.leap", args: [base]).text : base
    }

    /// "Bính Ngọ".
    static func yearName(_ year: Int) -> String {
        let c = LunarCalendar.canChi(ofLunarYear: year)
        return UserMessage(key: "lunar.year", args: [UserMessage(key: "lunar.stem.\(c.stem)").text,
                                                     UserMessage(key: "lunar.branch.\(c.branch)").text]).text
    }

    /// "Thứ Bảy, 6/2/2027" (weekday from Foundation's Vietnamese locale).
    static func solarName(_ s: SolarDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = LunarCalendar.vietnamTimeZone
        guard let date = calendar.date(from: DateComponents(year: s.year, month: s.month, day: s.day, hour: 12)) else {
            return "\(s.day)/\(s.month)/\(s.year)"
        }
        let weekday = date.formatted(Date.FormatStyle(timeZone: LunarCalendar.vietnamTimeZone)
            .locale(Locale(identifier: "vi-VN")).weekday(.wide))
        return UserMessage(key: "lunar.solarDate",
                           args: [weekday.prefix(1).uppercased() + weekday.dropFirst(), "\(s.day)/\(s.month)/\(s.year)"]).text
    }
}
