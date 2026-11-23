import Foundation

/// The value of a `lunarDate` field (DATA_MODEL §1.6, D-332): `[YYYY-]MM-DD[L][THH:mm]`.
/// Month token: `01`…`12`, `00` = every lunar month (with `lunarRecurrence = monthly`), or a month the phone resolves
/// because the LLM does not know today's lunar date: `N0` this lunar month, `N1` next lunar month, `NX` the next time
/// this lunar day comes ("rằm", "mùng 5 âm lịch"). `isLeap` / `year` only with `01`…`12`;
/// `year` only when the user named one; `hour` / `minute` only when said ("lúc 6 giờ sáng").
/// The LLM writes this string; the solar date is always computed by the app (`LunarCalendar`), never by the LLM.
struct LunarFieldValue: Codable, Sendable, Hashable {
    /// The month as said. `.number(0)` = every month.
    enum Month: Codable, Sendable, Hashable {
        case number(Int)
        case thisMonth, nextMonth, nextOccurrence
    }

    var year: Int?
    var monthToken: Month
    var day: Int
    var isLeap: Bool = false
    var hour: Int?
    var minute: Int?

    init(year: Int? = nil, month: Int, day: Int, isLeap: Bool = false, hour: Int? = nil, minute: Int? = nil) {
        self.init(year: year, monthToken: .number(month), day: day, isLeap: isLeap, hour: hour, minute: minute)
    }

    init(year: Int? = nil, monthToken: Month, day: Int, isLeap: Bool = false, hour: Int? = nil, minute: Int? = nil) {
        self.year = year; self.monthToken = monthToken; self.day = day; self.isLeap = isLeap
        self.hour = hour; self.minute = minute
    }

    /// The month number; 0 for every month and for the relative tokens (resolved on device, 4L.4).
    var month: Int { if case .number(let m) = monthToken { m } else { 0 } }

    /// nil when `value` is not a valid encoding.
    init?(_ value: String) {
        guard let m = value.wholeMatch(of: /(?:(\d{4})-)?(\d{2}|N0|N1|NX)-(\d{2})(L)?(?:T(\d{2}):(\d{2}))?/),
              let day = Int(m.3), (1...30).contains(day)
        else { return nil }
        let token: Month
        switch m.2 {
        case "N0": token = .thisMonth
        case "N1": token = .nextMonth
        case "NX": token = .nextOccurrence
        default:
            guard let n = Int(m.2), (0...12).contains(n) else { return nil }
            token = .number(n)
        }
        let year = m.1.flatMap { Int($0) }
        let isLeap = m.4 != nil
        // A year or "nhuận" needs a real month number (not every month, not a relative month).
        if (isLeap || year != nil) && (token == .number(0) || !Self.isNumber(token)) { return nil }
        var hour: Int?, minute: Int?
        if let h = m.5.flatMap({ Int($0) }), let mi = m.6.flatMap({ Int($0) }) {
            guard (0...23).contains(h), (0...59).contains(mi) else { return nil }
            hour = h; minute = mi
        }
        if let year, !(1800...2199).contains(year) { return nil }
        self.init(year: year, monthToken: token, day: day, isLeap: isLeap, hour: hour, minute: minute)
    }

    private static func isNumber(_ t: Month) -> Bool { if case .number = t { true } else { false } }

    var encoded: String {
        var s = year.map { String(format: "%04d-", $0) } ?? ""
        switch monthToken {
        case .number(let n): s += String(format: "%02d", n)
        case .thisMonth: s += "N0"
        case .nextMonth: s += "N1"
        case .nextOccurrence: s += "NX"
        }
        s += String(format: "-%02d", day)
        if isLeap { s += "L" }
        if let hour, let minute { s += String(format: "T%02d:%02d", hour, minute) }
        return s
    }

    var isEveryMonth: Bool { monthToken == .number(0) }
}
