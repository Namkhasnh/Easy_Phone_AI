import Foundation
import Testing
@testable import EasyPhoneAI

/// 2.5 — S21 Mail summary (UI_SCREENS S21, API_GMAIL §4, D-304, D-308, D-310).
@MainActor
@Suite("S21 Mail summary")
struct MailTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Date(timeIntervalSince1970: 1_794_877_200)   // 2026-11-17 08:00 +07:00

    func model(_ gmail: MockGmailService, _ api: MockAPIClient = MockAPIClient(),
               tts: MockTTSService = MockTTSService()) -> MailViewModel {
        let fixed = Self.now
        return MailViewModel(gmail: gmail, api: api, tts: tts, speechRate: 0.4, now: { fixed }, timeZone: Self.tz)
    }

    @Test func loadsTheSummaryWithANewKeyEachTime() async throws {
        let api = MockAPIClient()
        let vm = model(MockGmailService(accounts: [MockGmailService.sample]), api)
        await vm.load()
        #expect(vm.phase == .loaded(.mock))
        let call = try #require(api.gmailSummaryCalls.first)
        #expect(call.request.accountId == MockGmailService.sample.accountId)
        #expect(call.request.window == .unread && call.request.maxMessages == 10)
        #expect(!call.request.summarize && api.gmailSummaryCalls.last?.request.summarize == true)   // fast first
        #expect(call.request.now == "2026-11-17T08:00:00+07:00" && call.request.timezone == "Asia/Ho_Chi_Minh")
        #expect(api.gmailSummaryCalls.count == 2 && api.gmailSummaryCalls[1].key != call.key)
        await vm.load()                                                       // "Tải lại" = a new user action
        #expect(api.gmailSummaryCalls.count == 4 && !vm.isSummarizing)
    }

    @Test func noAccountOrDeadTokenAsksToConnect() async {
        let none = model(MockGmailService())
        await none.load()
        #expect(none.phase == .notConnected)

        let dead = GmailAccount(accountId: "gma_01JD0000000000000000000000", email: "k@gmail.com", status: .needsReconnect)
        let api = MockAPIClient()
        let expired = model(MockGmailService(accounts: [dead]), api)
        await expired.load()
        #expect(expired.phase == .needsReconnect && api.gmailSummaryCalls.isEmpty)   // no call, no unit

        let backendSaysSo = MockAPIClient()
        backendSaysSo.setGmailSummary(.failure(.api(code: "gmail_reconnect_required", retryable: false, details: nil,
                                                    requestId: nil)))
        let vm = model(MockGmailService(accounts: [MockGmailService.sample]), backendSaysSo)
        await vm.load()
        #expect(vm.phase == .needsReconnect)
    }

    @Test func connectFromTheEmptyStateThenLoads() async {
        let vm = model(MockGmailService())
        await vm.load()
        await vm.connect()
        #expect(vm.phase == .loaded(.mock))
    }

    @Test func errorsBecomeKeys() async {
        let api = MockAPIClient()
        api.setGmailSummary(.failure(.network(.offline)))
        let vm = model(MockGmailService(accounts: [MockGmailService.sample]), api)
        await vm.load()
        #expect(vm.phase == .failed(UserMessage(key: "error.network.offline")))
        api.setGmailSummary(.failure(.api(code: "quota_exceeded", retryable: false, details: nil, requestId: nil)))
        await vm.load()
        #expect(vm.phase == .failed(UserMessage(key: "error.quota_exceeded")))
    }

    @Test func readAloudTogglesAndSaysSenderSubjectSummary() async {
        let tts = MockTTSService()
        let vm = model(MockGmailService(accounts: [MockGmailService.sample]), tts: tts)
        let lan = GmailSummaryResponse.mock.messages[1]
        #expect(MailViewModel.spoken(lan) == "Nguyễn Thị Lan. Họp tổ chiều thứ Sáu. Chị Lan hỏi em có dự họp 15:00 thứ Sáu không.")
        await vm.toggleReading(lan.messageId, text: MailViewModel.spoken(lan))
        #expect(tts.spoken.last?.text == MailViewModel.spoken(lan))
        #expect(vm.readingId == nil)                                          // finished
    }

    @Test func moreCountAndStrings() {
        #expect(MailViewModel.moreCount(.mock) == 5)                           // totalFound 7, 2 shown
        for key in ["mail.title", "mail.account", "mail.empty", "mail.more", "mail.needsReply", "mail.refresh",
                    "mail.unreadNote", "error.gmail_not_connected", "error.gmail_reconnect_required"] {
            #expect(UserMessage(key: key).text != key, "missing string \(key)")
        }
        #expect(UserMessage(key: "mail.more", args: ["5"]).text == "Và 5 thư khác")
    }

    // MARK: - Verification code (D-311)

    static let otp = GmailMessageSummary(messageId: "18c4000", threadId: "t", fromName: "Google",
                                         subject: "482913 là mã xác minh Google của bạn", receivedAt: Self.now,
                                         summary: "Google gửi mã 482913 để đăng nhập.", needsReply: false,
                                         verificationCode: "482913")

    @Test func codeIsCopiedToADeviceOnlyClipboardAndNeverSpoken() async {
        let system = MockSystemService()
        let vm = MailViewModel(gmail: MockGmailService(accounts: [MockGmailService.sample]), api: MockAPIClient(),
                               system: system)
        await vm.copyCode(Self.otp)
        #expect(system.copied == ["482913"] && vm.copiedCodeId == "18c4000")
        let spoken = MailViewModel.spoken(Self.otp)
        #expect(!spoken.contains("482913"))
        #expect(spoken.hasSuffix(UserMessage(key: "mail.code.spoken").text))
        let response = GmailSummaryResponse(schemaVersion: 1, requestId: "r", accountEmail: "k@gmail.com", totalFound: 3,
                                            overview: "Có mã 482913 từ Google.",
                                            messages: GmailSummaryResponse.mock.messages + [Self.otp])
        #expect(!MailViewModel.spokenOverview(response).contains("482913"))
        #expect(MailViewModel.codes(response).map(\.messageId) == ["18c4000"])
        #expect(MailViewModel.codeClipboardSeconds == 120)
    }

    @Test func codeStrings() {
        for key in ["mail.code.title", "mail.code.from", "mail.code.copy", "mail.code.copied", "mail.code.warning",
                    "mail.code.spoken"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
    }

    // MARK: - Speed (owner 2026-11-18)

    @Test func checkMailIsUnderstoodOnTheDevice() {
        for text in ["Có thư mới không?", "kiểm tra mail giúp tôi", "xem mã gửi về", "đọc mã xác nhận", "mã OTP đâu",
                     "Gmail có gì mới"] {
            #expect(LocalIntent.isCheckMail(text), "\(text)")
        }
        for text in ["Soạn mail cho chị Lan", "gửi thư cho sếp nói mai em nghỉ", "trả lời thư của anh Minh",
                     "nhắn tin cho mẹ", "nhắc tôi uống thuốc", "gửi mã cho con"] {
            #expect(!LocalIntent.isCheckMail(text), "\(text)")
        }
    }

    @Test func summaryFailureKeepsTheListAndCodes() async {
        let api = MockAPIClient()
        let vm = model(MockGmailService(accounts: [MockGmailService.sample]), api)
        api.setGmailSummary(.success(.mock))
        await vm.load()
        #expect(vm.phase == .loaded(.mock) && vm.summaryNotice == nil)
    }
}
