import Foundation
import Testing
@testable import EasyPhoneAI

/// 4H.5 (D-337, D-325): the guide followed from another app: panel "tiếp" moves the shared step, S23 picks it up,
/// the Live Activity follows.
@MainActor
@Suite("Hướng dẫn trong panel Hỏi Khoai (4H.5)")
struct GuidePanelTests {
    let progress = MockGuideProgressService()
    let sessions: GuideSessions
    static let wifi = GuideLibrary.bundled.guides.first { $0.id == "iphone.wifi" }!.guide   // 4 steps
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        let suite = "test.guide.\(UUID().uuidString)"
        sessions = GuideSessions(suiteName: suite, progress: progress)
    }

    @Test func tiepMovesOnAndTheLastOneEnds() throws {
        sessions.start(Self.wifi, question: "Kết nối Wi-Fi thế nào?", now: Self.t0)
        #expect(progress.shown.last?.label == "Bước 1/4")
        guard case .step(let s2)? = sessions.handle("tiếp", now: Self.t0) else { Issue.record("no step"); return }
        #expect(s2.index == 1 && s2.label == "Bước 2/4")
        #expect(sessions.handle("nói lại", now: Self.t0) == .step(s2))
        guard case .step(let back)? = sessions.handle("quay lại", now: Self.t0) else { Issue.record("no back"); return }
        #expect(back.index == 0)
        for _ in 0..<3 { _ = sessions.handle("tiếp theo đi", now: Self.t0) }
        #expect(sessions.current(now: Self.t0)?.isLast == true)
        #expect(sessions.handle("tiếp", now: Self.t0) == .finished)
        #expect(sessions.current(now: Self.t0) == nil && progress.endCount == 1)
        #expect(progress.shown.map(\.step) == [1, 2, 2, 1, 2, 3, 4])
    }

    @Test func thoiStops() {
        sessions.start(Self.wifi, question: "wifi", now: Self.t0)
        #expect(sessions.handle("thôi", now: Self.t0) == .stopped)
        #expect(sessions.current(now: Self.t0) == nil)
    }

    @Test func noGuideOpen() {
        #expect(sessions.handle("tiếp", now: Self.t0) == .noGuide)
        #expect(sessions.handle("đặt báo thức", now: Self.t0) == nil)
    }

    /// Tasks with a guide word stay tasks (normal panel flow).
    @Test func longSentencesAreNotGuideWords() {
        sessions.start(Self.wifi, question: "wifi", now: Self.t0)
        #expect(sessions.handle("nhắc tôi tiếp tục uống thuốc lúc 8 giờ", now: Self.t0) == nil)
        #expect(sessions.handle("gọi cho con", now: Self.t0) == nil)
    }

    @Test func expiresAfterHalfAnHour() {
        sessions.start(Self.wifi, question: "wifi", now: Self.t0)
        #expect(sessions.current(now: Self.t0.addingTimeInterval(29 * 60)) != nil)
        #expect(sessions.current(now: Self.t0.addingTimeInterval(31 * 60)) == nil)
        #expect(progress.endCount == 1)
    }

    @Test func storedQuestionIsMasked() {
        sessions.start(Self.wifi, question: "mã OTP 482913 nhập ở đâu", now: Self.t0)
        #expect(sessions.current(now: Self.t0)?.question == "mã OTP ••• nhập ở đâu")
        #expect(sessions.current(for: "mã OTP 482913 nhập ở đâu", now: Self.t0) != nil)
    }

    // MARK: - Panel card

    @Test func stepCardSaysHowToGoOn() throws {
        let s = sessions.start(Self.wifi, question: "wifi", now: Self.t0)
        let reply = KhoaiPanel.guideReply(.step(s), first: true)
        #expect(reply.shown == "Bước 1/4")
        #expect(reply.full.hasPrefix(Self.wifi.title) && reply.full.contains("“tiếp”"))
        guard case .guide(let card) = reply.view.content else { Issue.record("not a guide card"); return }
        #expect(card.text == Self.wifi.steps[0].text && card.warning == nil && !card.canGoBack && card.canGoOn)
    }

    @Test func moneyStepKeepsTheOTPWarning() {
        let bank = GuideLibrary.bundled.guides.first { $0.id == "bank.transfer" }!.guide
        let s = sessions.start(bank, question: "chuyển tiền", now: Self.t0)
        guard case .guide(let card) = KhoaiPanel.guideReply(.step(s)).view.content else { Issue.record("card"); return }
        #expect(card.warning == UserMessage(key: "guide.warning.otp").text)          // D-339
    }

    // MARK: - S23 shares the step

    @Test func s23UsesThePanelGuideWithoutASecondUnit() async {
        let ai = GuideResponse.mock.guide!
        sessions.start(ai, question: "cách dùng app Grab")
        _ = sessions.handle("tiếp")
        let api = MockAPIClient()
        let vm = GuideViewModel(question: "cách dùng app Grab", api: api, sessions: sessions)
        await vm.load()
        #expect(api.guideCalls.isEmpty && vm.index == 1 && vm.isAIWritten)
    }

    @Test func s23StepsMoveThePanelAndBackFromZaloResumes() async {
        let vm = GuideViewModel(question: "Kết nối Wi-Fi thế nào?", api: MockAPIClient(), sessions: sessions)
        await vm.load()
        vm.tapNext()
        #expect(sessions.current()?.index == 1)
        _ = sessions.handle("tiếp")                                             // said to the panel in Cài đặt
        vm.resume()
        #expect(vm.index == 2)
        vm.leave()
        #expect(sessions.current() == nil)
    }
}
