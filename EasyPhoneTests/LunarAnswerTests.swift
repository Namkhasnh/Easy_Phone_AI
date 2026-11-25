import Foundation
import Testing
@testable import EasyPhoneAI

/// 4L.2 — lunar questions answered on the phone (D-330). Now = Mon 23/11/2026 10:00 (+07:00) = rằm tháng 10 Bính Ngọ.
@Suite("Lunar answers (4L.2)")
@MainActor
struct LunarAnswerTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00+07:00")!

    static func m(_ text: String) -> LocalIntent? { LocalIntent.match(text, now: now, timeZone: tz) }

    @Test(arguments: [
        ("Hôm nay âm lịch ngày mấy", LunarQuestion.today),
        ("Khoai ơi hôm nay là ngày bao nhiêu âm lịch", .today),
        ("ngày âm hôm nay là ngày gì", .today),
        ("âm lịch hôm nay", .today),
        ("Rằm tháng này là ngày nào", .fullMoon(monthOffset: 0)),
        ("rằm tháng sau ngày mấy dương lịch", .fullMoon(monthOffset: 1)),
        ("bao giờ đến rằm", .fullMoon(monthOffset: 0)),
        ("mùng 1 tháng tới là thứ mấy", .firstDay(monthOffset: 1)),
        ("Tết còn mấy ngày nữa", .tet),
        ("còn bao nhiêu ngày nữa đến Tết", .tet),
        ("bao giờ thì Tết", .tet),
        ("mùng 1 Tết là ngày nào", .tet),
    ])
    func matches(text: String, expected: LunarQuestion) {
        #expect(Self.m(text) == .lunar(expected), "\(text)")
    }

    /// Creating something, another lunar month, or another day → not answered here (AI / LocalSchedule as before).
    @Test(arguments: [
        "Nhắc tôi rằm tháng này thắp hương",
        "đặt lịch giỗ ông 10/3 âm",
        "rằm tháng 8 là ngày nào",
        "mùng 1 tháng Giêng là ngày nào dương lịch",
        "mai âm lịch là ngày mấy",
        "tạo lời nhắc mùng 1 hằng tháng",
        "nghỉ Tết",
        "gọi cho mẹ",
    ])
    func notMatched(text: String) {
        if case .lunar? = Self.m(text) { Issue.record("matched: \(text)") }
    }

    @Test func answers() {
        #expect(LunarQuestion.today.answer(now: Self.now) == "Hôm nay là 15 tháng 10 năm Bính Ngọ (âm lịch).")
        #expect(LunarQuestion.fullMoon(monthOffset: 0).answer(now: Self.now) == "Rằm tháng 10 âm lịch là Thứ Hai, 23/11/2026.")
        #expect(LunarQuestion.fullMoon(monthOffset: 1).answer(now: Self.now) == "Rằm tháng 11 âm lịch là Thứ Tư, 23/12/2026.")
        #expect(LunarQuestion.firstDay(monthOffset: 1).answer(now: Self.now) == "Mùng 1 tháng 11 âm lịch là Thứ Tư, 9/12/2026.")
        #expect(LunarQuestion.tet.answer(now: Self.now) == "Còn 75 ngày nữa là Tết Đinh Mùi (Thứ Bảy, 6/2/2027).")
    }

    @Test func namesFromTheCatalog() throws {
        #expect(LunarQuestion.dayName(5) == "mùng 5" && LunarQuestion.dayName(15) == "15")
        #expect(LunarQuestion.monthName(LunarDate(day: 1, month: 1, year: 2027)) == "Giêng")
        #expect(LunarQuestion.monthName(LunarDate(day: 1, month: 12, year: 2026)) == "Chạp")
        #expect(LunarQuestion.monthName(LunarDate(day: 1, month: 6, year: 2025, isLeap: true)) == "6 nhuận")
        let tetDay = try #require(ISO8601DateFormatter().date(from: "2027-02-06T08:00:00+07:00"))
        #expect(LunarQuestion.tet.answer(now: tetDay) == "Hôm nay là mùng 1 Tết Đinh Mùi. Chúc mừng năm mới!")
    }

    /// 2025 has a leap 6th month: the month after the regular 6th is "6 nhuận".
    @Test func nextMonthCountsTheLeapMonth() throws {
        let next = try #require(LunarQuestion.month(after: LunarDate(day: 20, month: 6, year: 2025), offset: 1))
        #expect(next.month == 6 && next.isLeap && next.year == 2025)
        let after = try #require(LunarQuestion.month(after: next, offset: 1))
        #expect(after.month == 7 && !after.isLeap)
    }

    /// S03: the answer shows in mode 6, the request is answered, nothing goes to `/v1/parse` (no unit).
    @Test func conversationAnswersOnThePhone() async {
        let repo = MockTaskRepository()
        let draft = TaskDraft(inputMode: .text, originalInput: "Tết còn mấy ngày", timeZoneId: "Asia/Ho_Chi_Minh")
        repo.save(draft)
        let api = MockAPIClient()
        let vm = ConversationViewModel(draftId: draft.id, repository: repo, speech: MockSpeechService(), api: api,
                                       tts: MockTTSService(), localData: MockLocalDataRepository(),
                                       engine: TaskEngine(repository: repo))
        await vm.onAppear()
        #expect(api.parseCalls.isEmpty)
        guard case .answer(let text) = vm.mode else { Issue.record("mode \(vm.mode)"); return }
        #expect(text.contains("Tết"))
        #expect(vm.mascotPose == .happy)
    }
}
