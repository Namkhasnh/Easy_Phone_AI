import Foundation
import Testing
@testable import EasyPhoneAI

/// D-330 / D-331 — Vietnamese lunar calendar (UTC+7), item 4L.1.
@Suite("Lunar calendar (D-330)")
struct LunarCalendarTests {
    static func s(_ y: Int, _ m: Int, _ d: Int) -> SolarDay { SolarDay(day: d, month: m, year: y) }

    /// Mùng 1 Tết of each lunar year (Vietnamese calendar). 1985 and 2007 differ from the Chinese calendar
    /// (China: 1985-02-20, 2007-02-18) — the reason D-330 forbids `Calendar(identifier: .chinese)`.
    /// 2030: the new moon is ~23:00 on 2/2 in Hanoi but after midnight in Beijing → VN 2/2, China 3/2 (computed;
    /// to be checked against a printed Vietnamese calendar, PROGRESS 4L.1).
    @Test(arguments: [
        (1985, 1985, 1, 21), (2007, 2007, 2, 17),
        (2020, 2020, 1, 25), (2021, 2021, 2, 12), (2022, 2022, 2, 1), (2023, 2023, 1, 22),
        (2024, 2024, 2, 10), (2025, 2025, 1, 29), (2026, 2026, 2, 17), (2027, 2027, 2, 6),
        (2028, 2028, 1, 26), (2029, 2029, 2, 13), (2030, 2030, 2, 2), (2031, 2031, 1, 23),
        (2032, 2032, 2, 11), (2033, 2033, 1, 31), (2034, 2034, 2, 19), (2035, 2035, 2, 8),
    ])
    func tet(lunarYear: Int, y: Int, m: Int, d: Int) {
        let solar = Self.s(y, m, d)
        #expect(LunarCalendar.lunar(from: solar) == LunarDate(day: 1, month: 1, year: lunarYear), "Tết \(lunarYear)")
        #expect(LunarCalendar.solar(from: LunarDate(day: 1, month: 1, year: lunarYear)) == solar, "Tết \(lunarYear)")
    }

    @Test func dayBeforeTetIsLastDayOfMonth12OfPreviousYear() {
        let l = LunarCalendar.lunar(from: Self.s(2024, 2, 9))
        #expect(l.month == 12 && l.year == 2023 && !l.isLeap && (l.day == 29 || l.day == 30))
    }

    /// Fixed holidays everyone in Vietnam knows: Giỗ Tổ Hùng Vương (10/3) and Trung thu (15/8).
    @Test(arguments: [
        (10, 3, 2023, 2023, 4, 29), (10, 3, 2024, 2024, 4, 18), (10, 3, 2025, 2025, 4, 7), (10, 3, 2026, 2026, 4, 26),
        (15, 8, 2024, 2024, 9, 17), (15, 8, 2025, 2025, 10, 6),
    ])
    func knownHolidays(ld: Int, lm: Int, ly: Int, y: Int, m: Int, d: Int) {
        #expect(LunarCalendar.solar(from: LunarDate(day: ld, month: lm, year: ly)) == Self.s(y, m, d))
        #expect(LunarCalendar.lunar(from: Self.s(y, m, d)) == LunarDate(day: ld, month: lm, year: ly))
    }

    @Test(arguments: [(2012, 4), (2014, 9), (2017, 6), (2020, 4), (2023, 2), (2025, 6), (2028, 5)])
    func leapMonths(year: Int, leap: Int) {
        #expect(LunarCalendar.leapMonth(inLunarYear: year) == leap, "\(year)")
    }

    @Test(arguments: [2019, 2021, 2022, 2024, 2026, 2027])
    func yearsWithoutLeapMonth(year: Int) {
        #expect(LunarCalendar.leapMonth(inLunarYear: year) == nil, "\(year)")
        #expect(LunarCalendar.solar(from: LunarDate(day: 1, month: 6, year: year, isLeap: true)) == nil)
    }

    /// 2025 has a leap 6th month: 1/6 = 25/6/2025, 1/6 nhuận = 25/7/2025.
    @Test func leapMonth2025() {
        #expect(LunarCalendar.solar(from: LunarDate(day: 1, month: 6, year: 2025)) == Self.s(2025, 6, 25))
        #expect(LunarCalendar.solar(from: LunarDate(day: 1, month: 6, year: 2025, isLeap: true)) == Self.s(2025, 7, 25))
        #expect(LunarCalendar.lunar(from: Self.s(2025, 7, 25)) == LunarDate(day: 1, month: 6, year: 2025, isLeap: true))
        #expect(LunarCalendar.solar(from: LunarDate(day: 1, month: 5, year: 2025, isLeap: true)) == nil)
    }

    @Test func invalidDatesAreNil() {
        #expect(LunarCalendar.solar(from: LunarDate(day: 31, month: 1, year: 2026)) == nil)
        #expect(LunarCalendar.solar(from: LunarDate(day: 0, month: 1, year: 2026)) == nil)
        #expect(LunarCalendar.solar(from: LunarDate(day: 1, month: 13, year: 2026)) == nil)
        for month in 1...12 {
            let length = LunarCalendar.monthLength(month: month, year: 2026)
            #expect(length == 29 || length == 30, "month \(month)")
            if length == 29 {
                #expect(LunarCalendar.solar(from: LunarDate(day: 30, month: month, year: 2026)) == nil)
            }
        }
    }

    /// Every day 1900 – 2100: solar → lunar → solar is the identity, and consecutive days step the lunar day by one
    /// or start a new month at day 1 after day 29 / 30.
    @Test func roundTripEveryDay1900To2100() {
        let first = LunarCalendar.julianDay(Self.s(1900, 1, 1))
        let last = LunarCalendar.julianDay(Self.s(2100, 12, 31))
        var previous: LunarDate?
        var failures = 0
        for jd in first...last {
            let solar = LunarCalendar.solarDay(julianDay: jd)
            let lunar = LunarCalendar.lunar(from: solar)
            if LunarCalendar.solar(from: lunar) != solar { failures += 1 }
            if let p = previous {
                let continues = lunar.day == p.day + 1 && lunar.month == p.month && lunar.isLeap == p.isLeap
                let newMonth = lunar.day == 1 && (p.day == 29 || p.day == 30)
                if !(continues || newMonth) { failures += 1 }
            }
            previous = lunar
            if failures > 5 { break }
        }
        #expect(failures == 0)
    }

    /// D-331: a yearly giỗ uses the regular month even in a year that has that month as leap; day 30 → 29 when needed.
    @Test func yearlyAnniversaryRules() throws {
        let inLeapYear = try #require(LunarCalendar.yearlyAnniversary(day: 1, month: 6, inLunarYear: 2025))
        #expect(inLeapYear.solar == Self.s(2025, 6, 25) && inLeapYear.adjustedDay == 1)

        let short = try #require((1...12).first { LunarCalendar.monthLength(month: $0, year: 2026) == 29 })
        let a = try #require(LunarCalendar.yearlyAnniversary(day: 30, month: short, inLunarYear: 2026))
        #expect(a.adjustedDay == 29)
        #expect(a.solar == LunarCalendar.solar(from: LunarDate(day: 29, month: short, year: 2026)))
    }

    @Test(arguments: [(2024, 0, 4), (2025, 1, 5), (2026, 2, 6), (1984, 0, 0), (2023, 9, 3)])
    func canChi(year: Int, stem: Int, branch: Int) {
        let c = LunarCalendar.canChi(ofLunarYear: year)
        #expect(c.stem == stem && c.branch == branch, "\(year)")   // Giáp Thìn, Ất Tỵ, Bính Ngọ, Giáp Tý, Quý Mão
    }

    /// The day is read on the Vietnamese clock: 2024-02-09 17:30 UTC is already Tết (00:30 on 10/2 in Hanoi).
    @Test func instantUsesVietnamTime() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2024-02-09T17:30:00Z"))
        #expect(LunarCalendar.lunar(from: date) == LunarDate(day: 1, month: 1, year: 2024))
    }
}
