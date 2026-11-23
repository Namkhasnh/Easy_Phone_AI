import Foundation

/// The value of a `lunarDate` field (DATA_MODEL §1.6, D-332): `[YYYY-]MM-DD[L][THH:mm]`.
/// `month == 0` = every lunar month (with `lunarRecurrence = monthly`); `isLeap` = the leap month (never with month 0);
/// `year` only when the user named one; `hour` / `minute` only when said ("lúc 6 giờ sáng").
/// The LLM writes this string; the solar date is always computed by the app (`LunarCalendar`), never by the LLM.
struct LunarFieldValue: Codable, Sendable, Hashable {
    var year: Int?
    var month: Int
    var day: Int
    var isLeap: Bool = false
    var hour: Int?
    var minute: Int?

    init(year: Int? = nil, month: Int, day: Int, isLeap: Bool = false, hour: Int? = nil, minute: Int? = nil) {
        self.year = year; self.month = month; self.day = day; self.isLeap = isLeap; self.hour = hour; self.minute = minute
    }

    /// nil when `value` is not a valid encoding.
    init?(_ value: String) {
        guard let m = value.wholeMatch(of: /(?:(\d{4})-)?(\d{2})-(\d{2})(L)?(?:T(\d{2}):(\d{2}))?/),
              let month = Int(m.2), let day = Int(m.3), (0...12).contains(month), (1...30).contains(day)
        else { return nil }
        let year = m.1.flatMap { Int($0) }
        let isLeap = m.4 != nil
        if month == 0 && (isLeap || year != nil) { return nil }          // "every month" has no year / leap
        var hour: Int?, minute: Int?
        if let h = m.5.flatMap({ Int($0) }), let mi = m.6.flatMap({ Int($0) }) {
            guard (0...23).contains(h), (0...59).contains(mi) else { return nil }
            hour = h; minute = mi
        }
        if let year, !(1800...2199).contains(year) { return nil }
        self.init(year: year, month: month, day: day, isLeap: isLeap, hour: hour, minute: minute)
    }

    var encoded: String {
        var s = year.map { String(format: "%04d-", $0) } ?? ""
        s += String(format: "%02d-%02d", month, day)
        if isLeap { s += "L" }
        if let hour, let minute { s += String(format: "T%02d:%02d", hour, minute) }
        return s
    }

    var isEveryMonth: Bool { month == 0 }
}
