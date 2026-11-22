import Foundation

/// A Vietnamese lunar date. `isLeap` = the day is in the leap (nhuận) month of that lunar year.
struct LunarDate: Codable, Sendable, Hashable {
    var day: Int
    var month: Int
    var year: Int
    var isLeap: Bool = false
}

/// A solar (Gregorian) calendar day, no time.
struct SolarDay: Codable, Sendable, Hashable, Comparable {
    var day: Int
    var month: Int
    var year: Int

    static func < (a: SolarDay, b: SolarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// D-330: Vietnamese lunar calendar computed on the phone (Hồ Ngọc Đức's algorithm, astronomical new moons and
/// solar terms) at **UTC+7**. Never `Calendar(identifier: .chinese)`: it uses UTC+8, and some years differ from the
/// Vietnamese calendar by a day or a whole month (Tết 1985, Tết 2007). Pure functions, no AI, no network.
/// Valid for years 1800 – 2199.
enum LunarCalendar {
    /// Vietnam's time zone, in hours. The lunar calendar is defined for this offset, not the phone's time zone.
    static let timeZoneHours = 7.0
    static let vietnamTimeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? TimeZone(secondsFromGMT: 7 * 3600)!

    // MARK: - Public API

    /// Solar day → lunar date.
    static func lunar(from solar: SolarDay) -> LunarDate {
        let dayNumber = julianDay(solar)
        let k = Int(floor((Double(dayNumber) - 2415021.076998695) / 29.530588853))
        var monthStart = newMoonDay(k + 1)
        if monthStart > dayNumber { monthStart = newMoonDay(k) }
        var back = k
        while monthStart > dayNumber { back -= 1; monthStart = newMoonDay(back) }   // estimate one month too late
        var a11 = lunarMonth11(solar.year)
        var b11 = a11
        var lunarYear: Int
        if a11 >= monthStart {
            lunarYear = solar.year
            a11 = lunarMonth11(solar.year - 1)
        } else {
            lunarYear = solar.year + 1
            b11 = lunarMonth11(solar.year + 1)
        }
        let lunarDay = dayNumber - monthStart + 1
        let diff = Int(floor(Double(monthStart - a11) / 29))
        var isLeap = false
        var lunarMonth = diff + 11
        if b11 - a11 > 365 {
            let leapDiff = leapMonthOffset(a11)
            if diff >= leapDiff {
                lunarMonth = diff + 10
                if diff == leapDiff { isLeap = true }
            }
        }
        if lunarMonth > 12 { lunarMonth -= 12 }
        if lunarMonth >= 11 && diff < 4 { lunarYear -= 1 }
        return LunarDate(day: lunarDay, month: lunarMonth, year: lunarYear, isLeap: isLeap)
    }

    /// The lunar date of an instant, read on the Vietnamese wall clock (UTC+7).
    static func lunar(from date: Date) -> LunarDate {
        lunar(from: solarDay(of: date))
    }

    /// Lunar date → solar day. `nil` when it does not exist: a leap month that year does not have, a day beyond the
    /// month's length (29 or 30), or values out of range.
    static func solar(from lunar: LunarDate) -> SolarDay? {
        guard (1...12).contains(lunar.month), (1...30).contains(lunar.day),
              let start = monthStartDayNumber(month: lunar.month, year: lunar.year, isLeap: lunar.isLeap),
              let length = monthLength(month: lunar.month, year: lunar.year, isLeap: lunar.isLeap),
              lunar.day <= length
        else { return nil }
        return solarDay(julianDay: start + lunar.day - 1)
    }

    /// 29 or 30; `nil` when that (leap) month does not exist.
    static func monthLength(month: Int, year: Int, isLeap: Bool = false) -> Int? {
        guard let start = monthStartDayNumber(month: month, year: year, isLeap: isLeap) else { return nil }
        let k = Int(floor(0.5 + (Double(start) - 2415021.076998695) / 29.530588853))
        var next = newMoonDay(k + 1)
        if next <= start { next = newMoonDay(k + 2) }
        return next - start
    }

    /// The leap month of a lunar year (1…12), or `nil` when the year has 12 months.
    static func leapMonth(inLunarYear year: Int) -> Int? {
        (1...12).first { monthStartDayNumber(month: $0, year: year, isLeap: true) != nil }
    }

    /// D-331: the solar day of a yearly anniversary (giỗ) given on lunar `day`/`month`, in lunar year `year`.
    /// Always the **regular** month (a leap month that year is skipped). A day 30 in a 29-day month → day 29;
    /// `adjustedDay` tells the UI so it can say so.
    static func yearlyAnniversary(day: Int, month: Int, inLunarYear year: Int) -> (solar: SolarDay, adjustedDay: Int)? {
        guard (1...12).contains(month), (1...30).contains(day),
              let length = monthLength(month: month, year: year, isLeap: false)
        else { return nil }
        let used = min(day, length)
        guard let solar = solar(from: LunarDate(day: used, month: month, year: year, isLeap: false)) else { return nil }
        return (solar, used)
    }

    /// Can Chi of a lunar year: stem index 0…9 (Giáp…Quý), branch index 0…11 (Tý…Hợi).
    /// Names are UI text and come from `Localizable.xcstrings` (keys `lunar.stem.<n>` / `lunar.branch.<n>`).
    // TODO(spec): Can Chi string keys are not in UI_SCREENS yet (added with the 4L screen items).
    static func canChi(ofLunarYear year: Int) -> (stem: Int, branch: Int) {
        (((year + 6) % 10 + 10) % 10, ((year + 8) % 12 + 12) % 12)
    }

    /// The Vietnamese wall-clock day of an instant.
    static func solarDay(of date: Date) -> SolarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = vietnamTimeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return SolarDay(day: c.day ?? 1, month: c.month ?? 1, year: c.year ?? 2000)
    }

    // MARK: - Algorithm (Hồ Ngọc Đức, "Âm lịch Việt Nam")

    /// Julian day number of a solar day (Gregorian after 1582-10-15, Julian before).
    static func julianDay(_ s: SolarDay) -> Int {
        let a = (14 - s.month) / 12
        let y = s.year + 4800 - a
        let m = s.month + 12 * a - 3
        var jd = s.day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        if jd < 2299161 {
            jd = s.day + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083
        }
        return jd
    }

    static func solarDay(julianDay jd: Int) -> SolarDay {
        let b: Int, c: Int
        if jd > 2299160 {
            let a = jd + 32044
            b = (4 * a + 3) / 146097
            c = a - (b * 146097) / 4
        } else {
            b = 0
            c = jd + 32082
        }
        let d = (4 * c + 3) / 1461
        let e = c - (1461 * d) / 4
        let m = (5 * e + 2) / 153
        return SolarDay(day: e - (153 * m + 2) / 5 + 1, month: m + 3 - 12 * (m / 10), year: b * 100 + d - 4800 + m / 10)
    }

    /// Julian day (fractional, UT) of the k-th new moon after 1900-01-01.
    private static func newMoon(_ k: Int) -> Double {
        let k = Double(k)
        let t = k / 1236.85
        let t2 = t * t, t3 = t2 * t
        let dr = Double.pi / 180
        var jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3
        jd1 += 0.00033 * sin((166.56 + 132.87 * t - 0.009173 * t2) * dr)
        let m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3
        let mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3
        let f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3
        var c1 = (0.1734 - 0.000393 * t) * sin(m * dr) + 0.0021 * sin(2 * dr * m)
        // Term by term, signs exactly as in the reference (`C1 = C1 - a + b` is NOT `c1 -= a + b`).
        c1 += -0.4068 * sin(mpr * dr) + 0.0161 * sin(dr * 2 * mpr)
        c1 += -0.0004 * sin(dr * 3 * mpr)
        c1 += 0.0104 * sin(dr * 2 * f) - 0.0051 * sin(dr * (m + mpr))
        c1 += -0.0074 * sin(dr * (m - mpr)) + 0.0004 * sin(dr * (2 * f + m))
        c1 += -0.0004 * sin(dr * (2 * f - m)) - 0.0006 * sin(dr * (2 * f + mpr))
        c1 += 0.0010 * sin(dr * (2 * f - mpr)) + 0.0005 * sin(dr * (2 * mpr + m))
        let deltaT: Double
        if t < -11 {
            deltaT = 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
        } else {
            deltaT = -0.000278 + 0.000265 * t + 0.000262 * t2
        }
        return jd1 + c1 - deltaT
    }

    /// Day number (local, UTC+7) of the k-th new moon.
    private static func newMoonDay(_ k: Int) -> Int {
        Int(floor(newMoon(k) + 0.5 + timeZoneHours / 24))
    }

    /// Sun's longitude in radians at a fractional Julian day (UT).
    private static func sunLongitude(_ jdn: Double) -> Double {
        let t = (jdn - 2451545.0) / 36525
        let t2 = t * t
        let dr = Double.pi / 180
        let m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2
        let l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2
        var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * sin(dr * m)
        dl += (0.019993 - 0.000101 * t) * sin(dr * 2 * m) + 0.000290 * sin(dr * 3 * m)
        var l = (l0 + dl) * dr
        l -= Double.pi * 2 * floor(l / (Double.pi * 2))
        return l
    }

    /// Solar-term sector 0…11 at the start of a local day.
    private static func sunLongitudeSector(_ dayNumber: Int) -> Int {
        Int(floor(sunLongitude(Double(dayNumber) - 0.5 - timeZoneHours / 24) / Double.pi * 6))
    }

    /// Day number of the start of lunar month 11 (the month containing the winter solstice) of solar year `year`.
    private static func lunarMonth11(_ year: Int) -> Int {
        let off = julianDay(SolarDay(day: 31, month: 12, year: year)) - 2415021
        let k = Int(floor(Double(off) / 29.530588853))
        var nm = newMoonDay(k)
        if sunLongitudeSector(nm) >= 9 { nm = newMoonDay(k - 1) }
        return nm
    }

    /// Offset (in months after month 11 starting at `a11`) of the leap month: the first month with no solar term.
    private static func leapMonthOffset(_ a11: Int) -> Int {
        let k = Int(floor((Double(a11) - 2415021.076998695) / 29.530588853 + 0.5))
        var i = 1
        var arc = sunLongitudeSector(newMoonDay(k + i))
        var last: Int
        repeat {
            last = arc
            i += 1
            arc = sunLongitudeSector(newMoonDay(k + i))
        } while arc != last && i < 14
        return i - 1
    }

    /// Day number of the first day of a lunar month, or `nil` for a leap month the year does not have.
    private static func monthStartDayNumber(month: Int, year: Int, isLeap: Bool) -> Int? {
        guard (1...12).contains(month) else { return nil }
        let a11: Int, b11: Int
        if month < 11 {
            a11 = lunarMonth11(year - 1)
            b11 = lunarMonth11(year)
        } else {
            a11 = lunarMonth11(year)
            b11 = lunarMonth11(year + 1)
        }
        let k = Int(floor(0.5 + (Double(a11) - 2415021.076998695) / 29.530588853))
        var off = month - 11
        if off < 0 { off += 12 }
        if b11 - a11 > 365 {
            let leapOff = leapMonthOffset(a11)
            // The leap month repeats the month before it: offset o ↔ month (11 + o) mod 12, 0 → 12.
            var leapMonth = (leapOff + 10) % 12
            if leapMonth == 0 { leapMonth = 12 }
            if isLeap && month != leapMonth { return nil }
            if isLeap || off >= leapOff { off += 1 }
        } else if isLeap {
            return nil
        }
        return newMoonDay(k + off)
    }
}
