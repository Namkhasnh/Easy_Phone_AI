import Foundation
import Testing
@testable import EasyPhoneAI

/// 4L.5 (D-331): lunar yearly / monthly series written one item per occurrence, idempotent by tag (D-105).
/// Now = Mon 23/11/2026 10:00 (+07:00) = 15/10 Bính Ngọ.
@MainActor
@Suite("Lunar series (4L.5)")
struct LunarSeriesTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00+07:00")!
    let repo = MockTaskRepository()

    func draft(_ kind: TaskKind, _ fields: [(String, String)]) -> TaskDraft {
        let parsed = ParsedDraft(schemaVersion: 1, requestId: nil, steps: [ParsedStep(
            kind: kind.rawValue, operation: "create",
            fields: fields.map { ParsedField(id: $0.0, value: $0.1, confidence: 0.9, sourceQuote: nil) },
            dateCandidates: [])], followUpQuestion: nil, unsupported: nil)
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh")
        TaskEngine(repository: repo, now: { Self.now }).applyParsed(parsed, to: d)
        repo.save(d)
        return d
    }

    static func day(_ date: Date) -> SolarDay { LunarCalendar.solarDay(of: date) }

    @Test func yearlyGiỗGivesFiveAllDayEventsWithTwoAlarms() async throws {
        let calendar = MockCalendarService()
        let engine = TaskEngine(repository: repo, executors: [
            .calendarEvent: CalendarExecutor(calendar: calendar, permissions: MockPermissionManager())], now: { Self.now })
        let d = draft(.calendarEvent, [("title", "Giỗ ông"), ("lunarDate", "03-10"), ("lunarRecurrence", "yearly")])
        engine.revalidate(stepId: d.steps[0].id, in: d)
        #expect(await engine.confirm(stepId: d.steps[0].id, in: d) == .finished(.succeeded))
        let events = calendar.all
        #expect(events.count == 5)
        // Each one is 10/3 âm of lunar years 2027 … 2031, all-day.
        for (i, e) in events.enumerated() {
            #expect(LunarCalendar.lunar(from: Self.day(e.start)) == LunarDate(day: 10, month: 3, year: 2027 + i), "\(i)")
            #expect(e.isAllDay && e.title == "Giỗ ông")
        }
        #expect(events[0].stepTag == StepTag.make(d.steps[0].id))
        #expect(events[1].stepTag == "\(StepTag.make(d.steps[0].id)):2028")
        #expect(events[0].alertMinutesBefore == 16 * 60)                              // 08:00 the day before
        #expect(d.steps[0].resultEvidence == "ek:event:\(events[0].id)")               // evidence = the first
    }

    @Test func retryDoesNotDuplicateTheSeries() async throws {
        let calendar = MockCalendarService()
        let executor = CalendarExecutor(calendar: calendar, permissions: MockPermissionManager())
        let d = draft(.calendarEvent, [("title", "Giỗ bà"), ("lunarDate", "07-20"), ("lunarRecurrence", "yearly")])
        _ = await executor.execute(d.steps[0], draft: d)
        _ = await executor.execute(d.steps[0], draft: d)                              // lost result → run again
        #expect(calendar.all.count == 5 && calendar.saveCount == 5)
    }

    @Test func monthlyReminderGivesTwelve() async throws {
        let reminders = MockRemindersService()
        let executor = RemindersExecutor(reminders: reminders, permissions: MockPermissionManager(),
                                         now: { Self.now }, morningHour: { 7 })
        let d = draft(.reminder, [("title", "Thắp hương"), ("lunarDate", "00-01T06:00"), ("lunarRecurrence", "monthly")])
        guard case .verified = await executor.execute(d.steps[0], draft: d) else { Issue.record("not verified"); return }
        let items = reminders.all
        #expect(items.count == 12)
        #expect(items.allSatisfy { r in r.dueDate.map { LunarCalendar.lunar(from: $0).day == 1 } ?? false })
        _ = await executor.execute(d.steps[0], draft: d)
        #expect(reminders.all.count == 12)                                             // idempotent (D-105)
    }

    @Test func oneTimeLunarStepWritesOneItem() async throws {
        let reminders = MockRemindersService()
        let executor = RemindersExecutor(reminders: reminders, permissions: MockPermissionManager(),
                                         now: { Self.now }, morningHour: { 7 })
        let d = draft(.reminder, [("title", "Đi chùa"), ("lunarDate", "N1-15")])
        _ = await executor.execute(d.steps[0], draft: d)
        #expect(reminders.all.count == 1)
    }

    /// D-331: a yearly date on day 30 uses 29 in the years whose month has 29 days.
    @Test func day30FollowsTheMonthLength() throws {
        let d = draft(.calendarEvent, [("title", "Giỗ cụ"), ("lunarDate", "03-30"), ("lunarRecurrence", "yearly")])
        let items = LunarSeries.following(d.steps[0], timeZoneId: "Asia/Ho_Chi_Minh")
        #expect(items.count == 4)
        for item in items {
            let l = LunarCalendar.lunar(from: Self.day(item.start))
            let length = try #require(LunarCalendar.monthLength(month: 3, year: l.year))
            #expect(l.month == 3 && l.day == min(30, length))
        }
    }

    // MARK: - Edit / delete the whole series (D-331)

    func step(_ kind: TaskKind, _ op: TaskOperation, _ values: [String: String], target: String) -> (TaskStep, TaskDraft) {
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: 0.9, deviceOnly: $0.deviceOnly)
        }
        let s = TaskStep(order: 0, kind: kind, operation: op, fields: fields, targetRef: target)
        return (s, TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [s]))
    }

    func giỗSeries(_ calendar: MockCalendarService) async throws -> CalendarExecutor {
        let executor = CalendarExecutor(calendar: calendar, permissions: MockPermissionManager())
        let d = draft(.calendarEvent, [("title", "Giỗ ông"), ("lunarDate", "03-10"), ("lunarRecurrence", "yearly")])
        _ = await executor.execute(d.steps[0], draft: d)
        _ = try await calendar.save(EventInput(title: "Khám răng", start: Self.now + 86_400, end: Self.now + 90_000),
                                    stepTag: "easyphone:other", existing: nil)
        return executor
    }

    @Test func deletingOneGiỗDeletesTheSeries() async throws {
        let calendar = MockCalendarService()
        let executor = try await giỗSeries(calendar)
        let middle = try #require(calendar.all.filter { $0.title == "Giỗ ông" }.dropFirst(2).first)
        let (s, d) = step(.calendarEvent, .delete, ["title": "Giỗ ông"], target: middle.id)
        guard case .verified = await executor.execute(s, draft: d) else { Issue.record("not verified"); return }
        #expect(calendar.all.map(\.title) == ["Khám răng"])                           // other events untouched
        #expect(calendar.deleted.count == 5 && calendar.deleted.last == middle.id)    // target last
    }

    @Test func renamingOneGiỗRenamesTheSeriesAndKeepsDates() async throws {
        let calendar = MockCalendarService()
        let executor = try await giỗSeries(calendar)
        let before = calendar.all.filter { $0.title == "Giỗ ông" }
        let first = before[0]
        let (s, d) = step(.calendarEvent, .update, [
            "title": "Giỗ ông nội", "startDate": "2027-04-16T00:00:00+07:00", "allDay": "true",
            "alertMinutesBefore": "960"], target: first.id)
        guard case .verified = await executor.execute(s, draft: d) else { Issue.record("not verified"); return }
        let after = calendar.all.filter { $0.title == "Giỗ ông nội" }
        #expect(after.map(\.start) == before.map(\.start))
        #expect(after.map(\.stepTag) == before.map(\.stepTag))                         // tags kept (D-105)
        #expect(calendar.all.contains { $0.title == "Khám răng" })
    }

    @Test func deletingOneMonthlyReminderDeletesTheOpenOnes() async throws {
        let reminders = MockRemindersService()
        let executor = RemindersExecutor(reminders: reminders, permissions: MockPermissionManager(),
                                         now: { Self.now }, morningHour: { 7 })
        let d = draft(.reminder, [("title", "Thắp hương"), ("lunarDate", "00-01T06:00"), ("lunarRecurrence", "monthly")])
        _ = await executor.execute(d.steps[0], draft: d)
        let items = reminders.all
        try await reminders.setCompleted(items[0].id, true)                           // done = history, kept
        let (s, sd) = step(.reminder, .delete, ["title": "Thắp hương"], target: items[3].id)
        guard case .verified = await executor.execute(s, draft: sd) else { Issue.record("not verified"); return }
        #expect(reminders.all.map(\.id) == [items[0].id])
    }

    // MARK: - Extend on launch (4L.6, D-331)

    /// 10/3 âm 2031 = the 5th giỗ; from then only it (and nothing after) is ahead → the next 5 years are due.
    static let in2030 = ISO8601DateFormatter().date(from: "2030-06-01T10:00:00+07:00")!

    @Test func noExtensionWhileTwoAreAhead() {
        let d = draft(.calendarEvent, [("title", "Giỗ ông"), ("lunarDate", "03-10"), ("lunarRecurrence", "yearly")])
        #expect(LunarSeries.extensionPlan(d.steps[0], timeZoneId: "Asia/Ho_Chi_Minh", now: Self.now) == nil)
        let plan = LunarSeries.extensionPlan(d.steps[0], timeZoneId: "Asia/Ho_Chi_Minh", now: Self.in2030)
        #expect(plan?.items.map(\.suffix) == ["2032", "2033", "2034", "2035", "2036"])
        #expect(plan?.ends.map(\.suffix) == ["2031"])
    }

    @Test func launchAddsTheNextFiveYearsOnce() async throws {
        let calendar = MockCalendarService()
        let executor = CalendarExecutor(calendar: calendar, permissions: MockPermissionManager())
        let d = draft(.calendarEvent, [("title", "Giỗ ông"), ("lunarDate", "03-10"), ("lunarRecurrence", "yearly")])
        _ = await executor.execute(d.steps[0], draft: d)
        #expect(await executor.extendSeries(d.steps[0], draft: d, now: Self.now) == 0)
        #expect(await executor.extendSeries(d.steps[0], draft: d, now: Self.in2030) == 5)
        #expect(await executor.extendSeries(d.steps[0], draft: d, now: Self.in2030) == 0)        // idempotent
        let years = calendar.all.map { LunarCalendar.lunar(from: Self.day($0.start)).year }
        #expect(years == Array(2027...2036))
    }

    @Test func deletedSeriesIsNotRecreated() async throws {
        let calendar = MockCalendarService()
        let executor = CalendarExecutor(calendar: calendar, permissions: MockPermissionManager())
        let d = draft(.calendarEvent, [("title", "Giỗ ông"), ("lunarDate", "03-10"), ("lunarRecurrence", "yearly")])
        _ = await executor.execute(d.steps[0], draft: d)
        for e in calendar.all { try await calendar.delete(identifier: e.id) }                  // deleted in Lịch
        #expect(await executor.extendSeries(d.steps[0], draft: d, now: Self.in2030) == 0)
        #expect(calendar.all.isEmpty)
    }

    @Test func monthlyReminderExtendsWithTwelveMore() async throws {
        let reminders = MockRemindersService()
        let executor = RemindersExecutor(reminders: reminders, permissions: MockPermissionManager(),
                                         now: { Self.now }, morningHour: { 7 })
        let d = draft(.reminder, [("title", "Thắp hương"), ("lunarDate", "00-01T06:00"), ("lunarRecurrence", "monthly")])
        _ = await executor.execute(d.steps[0], draft: d)
        let later = try #require(reminders.all.last?.dueDate) - 10 * 86_400                    // only the last one ahead
        #expect(await executor.extendSeries(d.steps[0], draft: d, now: later) == 12)
        #expect(reminders.all.count == 24)
    }
}
