import Foundation
import Testing
@testable import EasyPhoneAI

/// 4L.4 (D-331, D-332): lunarDate → first solar date on the phone. Now = Mon 23/11/2026 10:00 (+07:00) = 15/10 Bính Ngọ.
@Suite("Lunar resolver (4L.4)")
struct LunarResolverTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00+07:00")!
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    static func day(_ raw: String, _ r: LunarResolver.Recurrence = .none) -> SolarDay? {
        guard case .date(let o) = LunarResolver.resolve(LunarFieldValue(raw)!, recurrence: r, now: now) else { return nil }
        return o.solar
    }
    static func s(_ d: Int, _ m: Int, _ y: Int) -> SolarDay { SolarDay(day: d, month: m, year: y) }

    @Test(arguments: [
        ("03-10", s(16, 4, 2027)),          // next 10/3 (Giỗ Tổ 2027)
        ("N0-15", s(23, 11, 2026)),         // rằm this month = today
        ("N1-15", s(23, 12, 2026)),         // rằm next month
        ("NX-20", s(28, 11, 2026)),         // 20/10 still ahead
        ("NX-05", s(13, 12, 2026)),         // 5/10 passed → 5/11
        ("00-01", s(9, 12, 2026)),          // every month, first: mùng 1 tháng 11
        ("00-15T06:00", s(23, 12, 2026)),   // today is rằm but 06:00 has passed → next month
        ("00-15T18:00", s(23, 11, 2026)),   // later today → today
        ("2025-06-01L", s(25, 7, 2025)),    // an explicit lunar year keeps the date said
    ])
    func firstDate(raw: String, expected: SolarDay) {
        #expect(Self.day(raw, raw.hasPrefix("00") ? .monthly : .none) == expected, "\(raw)")
    }

    /// D-331: day 30 in a 29-day month → 29 (3rd month of 2027 has 29 days), flagged for the UI.
    @Test func day30BecomesDay29() throws {
        guard case .date(let o) = LunarResolver.resolve(LunarFieldValue("03-30")!, recurrence: .yearly, now: Self.now)
        else { Issue.record("no date"); return }
        #expect(o.adjustedDay && o.lunar.day == 29 && o.lunar.month == 3 && o.lunar.year == 2027)
    }

    /// D-331: a yearly date said in a leap month → the user picks (regular 6th month 2027, or the next leap 6th, 2036).
    @Test func yearlyLeapMonthAsks() throws {
        guard case .choose(let options) = LunarResolver.resolve(LunarFieldValue("06-01L")!, recurrence: .yearly, now: Self.now)
        else { Issue.record("expected a choice"); return }
        #expect(options.map(\.solar.year) == [2027, 2036])
        #expect(!options[0].lunar.isLeap && options[1].lunar.isLeap)
        #expect(Self.day("06-01L")?.year == 2036)                        // one-time: the leap month itself
    }

    @Test func dateTimeValue() throws {
        guard case .date(let o) = LunarResolver.resolve(LunarFieldValue("03-10")!, recurrence: .yearly, now: Self.now)
        else { Issue.record("no date"); return }
        #expect(LunarResolver.dateTime(o, hour: nil, minute: nil, defaultHour: 8, timeZone: Self.tz) == "2027-04-16T08:00:00+07:00")
        #expect(LunarResolver.dateTime(o, hour: 6, minute: 30, defaultHour: 8, timeZone: Self.tz) == "2027-04-16T06:30:00+07:00")
    }

    // MARK: - DraftBuilder

    static func parsed(_ kind: String, _ fields: [(String, String)]) -> ParsedStep {
        ParsedStep(kind: kind, operation: "create",
                   fields: fields.map { ParsedField(id: $0.0, value: $0.1, confidence: 0.9, sourceQuote: nil) },
                   dateCandidates: [])
    }

    @Test func giỗBecomesAnAllDayEvent() throws {
        let step = try #require(DraftBuilder.step(from: Self.parsed("calendarEvent", [
            ("title", "Giỗ ông"), ("lunarDate", "03-10"), ("lunarRecurrence", "yearly")]), order: 0, now: Self.now))
        #expect(step.field("startDate")?.value == "2027-04-16T00:00:00+07:00")
        #expect(step.field("startDate")?.source == .device(origin: "lunar"))
        #expect(step.field("allDay")?.value == "true")
        #expect(step.state != .needsInfo)                                       // no follow-up for the date
    }

    @Test func monthlyReminderAtTheSaidHour() throws {
        let step = try #require(DraftBuilder.step(from: Self.parsed("reminder", [
            ("title", "Thắp hương"), ("lunarDate", "00-01T06:00"), ("lunarRecurrence", "monthly")]), order: 0, now: Self.now))
        #expect(step.field("dueDate")?.value == "2026-12-09T06:00:00+07:00")
    }

    @Test func yearlyLeapGivesADateAmbiguity() throws {
        let step = try #require(DraftBuilder.step(from: Self.parsed("calendarEvent", [
            ("title", "Giỗ bà"), ("lunarDate", "06-01L"), ("lunarRecurrence", "yearly")]), order: 0, now: Self.now))
        let a = try #require(step.field("startDate")?.ambiguity)
        #expect(a.kind == .date && a.candidates.count == 2 && step.field("startDate")?.value == nil)
        #expect(a.candidates[0].title == "1/6 âm lịch" && a.candidates[1].title == "1/6 nhuận âm lịch")
    }

    @Test func noLunarDateChangesNothing() throws {
        let step = try #require(DraftBuilder.step(from: Self.parsed("reminder", [
            ("title", "Uống thuốc"), ("dueDate", "2026-11-23T20:00:00+07:00")]), order: 0, now: Self.now))
        #expect(step.field("dueDate")?.value == "2026-11-23T20:00:00+07:00" && step.field("dueDate")?.source == .ai)
    }
}
