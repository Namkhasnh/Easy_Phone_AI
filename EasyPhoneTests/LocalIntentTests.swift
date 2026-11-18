import Foundation
import Testing
@testable import EasyPhoneAI

/// D-313 — requests understood on the phone (no `/v1/parse`), and the ones that must still go to the AI.
@MainActor
@Suite("Local intents (D-313)")
struct LocalIntentTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-18T20:00:00+07:00")!

    func match(_ text: String) -> LocalIntent? { LocalIntent.match(text, now: Self.now, timeZone: Self.tz) }

    @Test func calls() {
        #expect(match("Gọi cho mẹ") == .call(name: "mẹ"))
        #expect(match("gọi điện cho anh Minh nhé") == .call(name: "anh Minh"))
        #expect(match("Khoai ơi gọi điện thoại cho bà ngoại") == .call(name: "bà ngoại"))
        #expect(match("gọi mẹ") == .call(name: "mẹ"))
        for text in ["gọi cho mẹ lúc 8 giờ", "gọi số 0901234567", "gọi FaceTime cho mẹ", "gọi video cho con",
                     "gọi lại cho anh Minh sau", "nhắc tôi gọi cho mẹ", "gọi cho mẹ tối nay", "gọi"] {
            #expect(match(text) == nil, "\(text) must go to the AI")
        }
    }

    @Test func calendarDays() {
        #expect(match("Xem lịch hôm nay") == .calendarDay("2026-11-18"))
        #expect(match("xem lịch trình ngày mai") == .calendarDay("2026-11-19"))
        #expect(match("mai tôi có lịch gì không") == .calendarDay("2026-11-19"))
        #expect(match("lịch ngày kia") == .calendarDay("2026-11-20"))
        for text in ["đặt lịch hôm nay lúc 3 giờ", "xóa lịch ngày mai", "xem lịch thứ Sáu", "hẹn lịch khám mai",
                     "thêm lịch họp ngày mai"] {
            #expect(match(text) == nil, "\(text) must go to the AI")
        }
    }

    @Test func directionsAndReminders() {
        #expect(match("Chỉ đường về nhà") == .directions(label: "home"))
        #expect(match("dẫn đường đến công ty nhé") == .directions(label: "work"))
        #expect(match("chỉ đường tới chỗ làm") == .directions(label: "work"))
        #expect(match("chỉ đường đến bệnh viện Chợ Rẫy") == nil)                  // a real search → AI
        #expect(match("Xem lời nhắc") == .reminders)
        #expect(match("lời nhắc của tôi") == .reminders)
        #expect(match("nhắc tôi uống thuốc") == nil)
    }

    @Test func mailStillFirst() {
        #expect(match("xem mã gửi về") == .checkMail(codesOnly: true))
        #expect(match("có thư mới không") == .checkMail(codesOnly: false))
        #expect(match("Soạn thư cho chị Lan") == nil)
    }

    @Test func aLocalCallBecomesANormalStepWithoutTheBackend() async throws {
        let repo = MockTaskRepository()
        let api = MockAPIClient()
        let draft = TaskDraft(inputMode: .text, originalInput: "Gọi cho mẹ", timeZoneId: "Asia/Ho_Chi_Minh")
        repo.save(draft)
        let vm = ConversationViewModel(draftId: draft.id, repository: repo, speech: MockSpeechService(), api: api,
                                       tts: MockTTSService(), localData: MockLocalDataRepository(),
                                       engine: TaskEngine(repository: repo))
        await vm.onAppear()
        #expect(api.parseCalls.isEmpty)                                         // no AI, no unit
        let step = try #require(repo.draft(draft.id)?.steps.first)
        #expect(step.kind == .call && step.operation == .open)
        #expect(step.field("recipientName")?.value == "mẹ" && step.field("callType")?.value == "phone")
    }

    @Test func remindersAndCalendarOpenScreens() async {
        for (text, check) in [("Xem lời nhắc", 0), ("xem lịch ngày mai", 1)] {
            let repo = MockTaskRepository()
            let draft = TaskDraft(inputMode: .text, originalInput: text, timeZoneId: "Asia/Ho_Chi_Minh")
            repo.save(draft)
            let api = MockAPIClient()
            let vm = ConversationViewModel(draftId: draft.id, repository: repo, speech: MockSpeechService(), api: api,
                                           tts: MockTTSService(), localData: MockLocalDataRepository(),
                                           engine: TaskEngine(repository: repo))
            await vm.onAppear()
            #expect(api.parseCalls.isEmpty)
            if check == 0 { #expect(vm.opensReminders) } else { #expect(vm.calendarDay != nil) }
        }
    }
}
