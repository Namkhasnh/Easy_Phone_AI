import Foundation
import Testing
@testable import EasyPhoneAI

/// S22 "Ngày giỗ & lễ" (4L.6). Now = Mon 23/11/2026 10:00 (+07:00) = 15/10 Bính Ngọ.
@MainActor
@Suite("Lunar days screen (4L.6)")
struct LunarDaysTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00+07:00")!
    let repo = MockTaskRepository()
    let calendar = MockCalendarService()

    func savedGiỗ() async -> TaskDraft {
        let parsed = ParsedDraft(schemaVersion: 1, requestId: nil, steps: [ParsedStep(
            kind: "calendarEvent", operation: "create",
            fields: [("title", "Giỗ ông"), ("lunarDate", "03-10"), ("lunarRecurrence", "yearly")]
                .map { ParsedField(id: $0.0, value: $0.1, confidence: 0.9, sourceQuote: nil) },
            dateCandidates: [])], followUpQuestion: nil, unsupported: nil)
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh")
        let engine = TaskEngine(repository: repo, executors: [
            .calendarEvent: CalendarExecutor(calendar: calendar, permissions: MockPermissionManager())], now: { Self.now })
        engine.applyParsed(parsed, to: d)
        repo.save(d)
        engine.revalidate(stepId: d.steps[0].id, in: d)
        _ = await engine.confirm(stepId: d.steps[0].id, in: d)
        return d
    }

    var vm: LunarDaysViewModel {
        LunarDaysViewModel(repository: repo, calendar: calendar, reminders: MockRemindersService(),
                           permissions: MockPermissionManager(), now: { Self.now })
    }

    @Test func listsTheSavedGiỗAndTheHolidays() async throws {
        _ = await savedGiỗ()
        let vm = vm
        await vm.load()
        #expect(vm.todayLine == "Hôm nay là 15 tháng 10 năm Bính Ngọ (âm lịch).")
        let row = try #require(vm.saved.first)
        #expect(vm.saved.count == 1 && row.title == "Giỗ ông" && row.lunarLabel == "10/3 âm lịch")
        #expect(row.nextLabel.hasSuffix("16/4/2027 · còn 144 ngày"))
        #expect(vm.holidays.count == 8)
        #expect(vm.holidays.first?.title == "Ông Công ông Táo")                    // 23/12 = 1/2/2027, the nearest
        #expect(vm.holidays.map(\.daysLeft) == vm.holidays.map(\.daysLeft).sorted())
    }

    @Test func deletedSeriesIsNotListed() async throws {
        _ = await savedGiỗ()
        for e in calendar.all { try await calendar.delete(identifier: e.id) }
        let vm = vm
        await vm.load()
        #expect(vm.saved.isEmpty && vm.loaded)
    }
}
