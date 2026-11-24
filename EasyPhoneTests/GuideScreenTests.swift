import Foundation
import Testing
@testable import EasyPhoneAI

/// 4H.3 (D-337, D-338, D-339, D-340, D-312): routing "làm sao …" to S23, masking, money flag, steps, hands-free "tiếp".
@MainActor
@Suite("Khoai hướng dẫn (4H.3)")
struct GuideScreenTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00+07:00")!
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    func intent(_ text: String) -> LocalIntent? { LocalIntent.match(text, now: Self.now, timeZone: Self.tz) }

    // MARK: - Routing

    @Test(arguments: [
        "Làm sao gửi ảnh qua Zalo",
        "chỉ tôi cách tăng cỡ chữ",
        "tăng cỡ chữ",                                               // phone setting without a question word
        "chụp màn hình",
        "gọi video Zalo thế nào",
        "Nhân viên ngân hàng xin mã OTP, tôi xem mã ở đâu để đọc cho họ?",   // never the code list (D-339)
        "hướng dẫn chuyển tiền qua app ngân hàng",
    ])
    func guideQuestions(text: String) {
        #expect(intent(text) == .guide(question: text), "\(text)")
    }

    @Test(arguments: [
        "nhắn Zalo cho Minh tối nay về ăn cơm",                      // a task
        "gửi ảnh cho con qua Zalo",                                  // a task said without a question word
        "nhắc tôi 8 giờ sáng mai uống thuốc",
        "chỉ đường đến chợ Bến Thành",
        "nhà thuốc gần nhất ở đâu",
        "Tết còn mấy ngày",
    ])
    func notGuideQuestions(text: String) {
        if case .guide = intent(text) { Issue.record("\(text)") }
    }

    @Test func plainCodeQuestionStillOpensMail() {
        #expect(intent("xem mã gửi về") == .checkMail(codesOnly: true))
    }

    // MARK: - Masking / money (D-339, D-340)

    @Test(arguments: [
        ("mã OTP là 482913 đọc cho ai", "mã OTP là ••• đọc cho ai"),
        ("số tài khoản 0123456789 chuyển 500 nghìn", "số tài khoản ••• chuyển 500 nghìn"),
        ("thẻ 4111 1111 1111 1111", "thẻ •••"),
        ("mật khẩu là abc123", "mật khẩu là •••"),
        ("chuyển 2 triệu cho con", "chuyển 2 triệu cho con"),
        ("200k", "200k"),
    ])
    func masks(input: String, expected: String) {
        #expect(GuideSafety.masked(input) == expected)
    }

    @Test func moneyKeywords() {
        #expect(GuideSafety.isMoneyRelated("Chuyển khoản cho con thế nào"))
        #expect(GuideSafety.isMoneyRelated("nhập mã OTP ở đâu"))
        #expect(!GuideSafety.isMoneyRelated("tăng cỡ chữ"))
    }

    // MARK: - Screen

    @Test func curatedGuideNeedsNoAI() async {
        let api = MockAPIClient()
        let vm = GuideViewModel(question: "Kết nối Wi-Fi thế nào?", api: api)
        await vm.load()
        #expect(vm.guide?.source == .curated(id: "iphone.wifi"))
        #expect(api.guideCalls.isEmpty)                                       // D-338: no unit
        #expect(!vm.isMoneyRelated && vm.stepLabel == "Bước 1/4")
        vm.next(); vm.next(); vm.next(); vm.next()
        #expect(vm.index == 3 && vm.isLast)
        vm.previous()
        #expect(vm.index == 2)
    }

    @Test func aiGuideGetsTheMaskedQuestion() async {
        let api = MockAPIClient()
        let vm = GuideViewModel(question: "Con bị tai nạn, chuyển tiền vào số 0123456789 thế nào", api: api)
        await vm.load()
        #expect(api.guideCalls.first?.request.question == "Con bị tai nạn, chuyển tiền vào số ••• thế nào")
        #expect(vm.isAIWritten && vm.isMoneyRelated)
        #expect(vm.spokenWarnings.contains("OTP") && vm.spokenWarnings.contains("Bệnh viện"))   // fixed + AI
    }

    @Test func notAGuideIsUnsupported() async {
        let response = GuideResponse(schemaVersion: 1, requestId: "r", title: nil, steps: [], isMoneyRelated: false,
                                     scamWarnings: [], unsupported: "notAGuide")
        let vm = GuideViewModel(question: "giá vàng hôm nay thế nào", api: MockAPIClient(guide: .success(response)))
        await vm.load()
        #expect(vm.phase == .unsupported)
    }

    @Test func retryUsesTheSameKey() async {
        let api = MockAPIClient(guide: .failure(.api(code: APIErrorCode.upstreamError, retryable: true, details: nil,
                                                     requestId: nil)))
        let vm = GuideViewModel(question: "cách dùng app Grab", api: api)
        await vm.load()
        #expect(vm.phase == .failed(UserMessage(key: "error.upstream_error")))
        await vm.load()
        #expect(api.guideCalls.count == 2 && api.guideCalls[0].key == api.guideCalls[1].key)   // D-245
    }

    @Test func handsFreeSaysTiepToTheEnd() async {
        let speech = MockSpeechService()
        speech.script = [Transcript(text: "tiếp", isFinal: true, confidence: 0.9)]
        let tts = MockTTSService()
        let vm = GuideViewModel(question: "Kết nối Wi-Fi thế nào?", spoken: true, api: MockAPIClient(), tts: tts,
                                speech: speech)
        await vm.load()
        await vm.waitForHandsFree()
        #expect(vm.index == 3)
        #expect(tts.spoken.count == 4 && tts.spoken[0].text.hasPrefix("Bước 1/4"))
        #expect(speech.startCount == 3)                                          // no listening after the last step
    }

    @Test func handsFreeStopsOnThoi() async {
        let speech = MockSpeechService()
        speech.script = [Transcript(text: "thôi", isFinal: true, confidence: 0.9)]
        let vm = GuideViewModel(question: "Kết nối Wi-Fi thế nào?", spoken: true, api: MockAPIClient(),
                                tts: MockTTSService(), speech: speech)
        await vm.load()
        await vm.waitForHandsFree()
        #expect(vm.index == 0)
    }

    @Test(arguments: [("tiếp", GuideVoiceCommand.next), ("tiếp theo đi", .next), ("nói lại", .repeatStep),
                      ("quay lại", .previous), ("thôi", .stop), ("hôm nay trời đẹp quá", .other)])
    func voiceCommands(text: String, expected: GuideVoiceCommand) {
        #expect(GuideVoiceCommand.classify(text) == expected)
    }
}

/// 4H.4 (D-339): "Gọi cho con trước khi chuyển" = a normal call request, confirmed by tap in S04.
@MainActor
@Suite("Gọi cho con (4H.4)")
struct GuideCallFamilyTests {
    @Test func buttonMakesACallRequestForCon() async throws {
        let repo = MockTaskRepository()
        let vm = GuideViewModel(question: "Hướng dẫn chuyển tiền qua app ngân hàng", api: MockAPIClient(),
                                repository: repo, timeZoneId: "Asia/Ho_Chi_Minh")
        await vm.load()
        #expect(vm.isMoneyRelated)
        let id = try #require(vm.callFamilyDraft())
        let draft = try #require(repo.draft(id))
        #expect(draft.originalInput == "Gọi cho con" && draft.steps.isEmpty)      // nothing runs before S04
        #expect(LocalIntent.match(draft.originalInput) == .call(name: "con"))     // on device, no unit
    }

    /// D-339 hard rules on every curated money guide.
    @Test func curatedMoneyGuidesNeverGiveAVerdict() {
        for g in GuideLibrary.bundled.guides where g.isMoneyRelated {
            for s in g.steps {
                let t = GuideLibrary.fold(s.text + " " + (s.hint ?? ""))
                for bad in ["an toan", "yen tam", "dang tin", "khong phai lua dao"] {
                    #expect(!t.contains(bad), "\(g.id): \(bad)")
                }
            }
        }
    }
}
