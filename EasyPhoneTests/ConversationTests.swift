import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.4a — UI_SCREENS S03 modes 1–2, spec §6.2 AC1 / AC5, API_CONTRACT §7.4 (never auto-send), D-104.
@MainActor
@Suite("Conversation listen + transcript (UI_SCREENS S03)")
struct ConversationTests {
    let repo = MockTaskRepository()
    let speech = MockSpeechService()
    let tts = MockTTSService()
    let local = MockLocalDataRepository()
    let api = MockAPIClient()

    func model(draftId: UUID? = nil, api: MockAPIClient? = nil) -> ConversationViewModel {
        ConversationViewModel(draftId: draftId, repository: repo, speech: speech, api: api ?? self.api, tts: tts,
                              localData: local)
    }

    // MARK: - 1B.12b `/v1/transcribe` fallback (ARCHITECTURE §4.3, §9.2; API_CONTRACT §7.4)

    static let audio = Data("m4a".utf8)

    @Test func viUnavailableUploadsRecordingAndShowsEditableText() async throws {
        speech.script = []
        speech.error = .unavailable("speech.vi.unavailable")
        speech.audio = Self.audio
        let vm = model()
        await vm.onAppear()
        #expect(api.transcribeCalls == [Self.audio])
        #expect(vm.mode == .transcript)                                   // editable, never sent (AC1)
        #expect(vm.text == "nhắn anh minh là chiều nay em đến muộn")
        #expect(vm.noticeKey == nil)
        #expect(api.parseCalls.isEmpty)
        let id = try #require(vm.draftId)
        #expect(repo.draft(id)?.originalInput == vm.text)                 // D-104
    }

    @Test func transcribeRateLimitedFallsBackToKeyboardAndKeepsText() async throws {
        let limited = MockAPIClient(transcribe: .failure(.api(code: APIErrorCode.rateLimited, retryable: true,
                                                              details: nil, requestId: nil)))
        let saved = TaskDraft(createdAt: .now, inputMode: .voice, originalInput: "Gọi cho mẹ")
        repo.save(saved)
        let vm = model(draftId: saved.id, api: limited)
        speech.script = []
        speech.error = .unavailable("speech.vi.unavailable")
        speech.audio = Self.audio
        await vm.speakAgain()
        #expect(limited.transcribeCalls.count == 1)
        #expect(vm.mode == .transcript)
        #expect(vm.noticeKey == "conv.speech.unavailable")
        #expect(vm.text == "Gọi cho mẹ")                                   // a failed retry loses nothing
    }

    @Test func emptyTranscriptAsksAgain() async {
        let empty = MockAPIClient(transcribe: .success(TranscribeResponse(schemaVersion: 1, requestId: "r", text: "  ",
                                                                          confidence: nil)))
        speech.script = []
        speech.error = .unavailable("speech.vi.unavailable")
        speech.audio = Self.audio
        let vm = model(api: empty)
        await vm.onAppear()
        #expect(vm.mode == .transcript && vm.noticeKey == "conv.speech.empty")
        #expect(vm.draftId == nil)
    }

    @Test func otherSpeechErrorsDoNotUpload() async {
        speech.script = []
        speech.error = .framework(code: "speech.failed")
        speech.audio = Self.audio
        let vm = model()
        await vm.onAppear()
        #expect(api.transcribeCalls.isEmpty)
        #expect(vm.noticeKey == "conv.speech.unavailable")
    }

    @Test func followUpAnswerUsesTheFallbackToo() async {
        let vm = model()
        vm.showFollowUp(.init(question: "Mấy giờ?"))
        speech.script = []
        speech.error = .unavailable("speech.vi.unavailable")
        speech.audio = Self.audio
        await vm.listenForAnswer()
        #expect(vm.mode == .followUp(.init(question: "Mấy giờ?")))
        #expect(vm.answerText == "nhắn anh minh là chiều nay em đến muộn")
        #expect(vm.text.isEmpty)                                           // the request is untouched
    }

    @Test func micEntryListensThenShowsEditableTranscriptAndSavesDraft() async throws {
        let vm = model()
        await vm.onAppear()
        #expect(speech.startCount == 1)
        #expect(speech.lastLocale?.identifier == "vi-VN")
        #expect(vm.mode == .transcript)
        #expect(vm.text == "Nhắc tôi 8 giờ sáng mai uống thuốc")
        #expect(vm.noticeKey == nil)
        let id = try #require(vm.draftId)                                    // D-104: saved as soon as there is text
        #expect(repo.draft(id)?.originalInput == vm.text)
        #expect(repo.draft(id)?.inputMode == .voice)
        #expect(repo.draft(id)?.steps.isEmpty == true)
    }

    @Test func listeningStopsReadingFirst() async {
        let vm = model()
        await vm.onAppear()
        Task { await vm.toggleReading() }
        await Task.yield()
        await vm.speakAgain()                                                // AC5: TTS stops when listening starts
        #expect(tts.spoken.count == 1)
        #expect(!vm.isReading)
    }

    @Test func editsAutosave() async throws {
        let vm = model()
        await vm.onAppear()
        vm.text = "Nhắc tôi 9 giờ sáng mai uống thuốc"
        let id = try #require(vm.draftId)
        let draft = try #require(repo.draft(id))
        #expect(draft.originalInput == "Nhắc tôi 9 giờ sáng mai uống thuốc")
    }

    @Test func unavailableShowsKeyboardMessageAndCreatesNothing() async {
        speech.script = []
        speech.error = .unavailable("speech.vi.unavailable")
        let vm = model()
        await vm.onAppear()
        #expect(vm.mode == .transcript)
        #expect(vm.noticeKey == "conv.speech.unavailable")
        #expect(vm.draftId == nil && repo.saveCount == 0)
        #expect(UserMessage(key: "conv.speech.unavailable").text == "Máy chưa nghe được tiếng Việt lúc này. Bạn gõ chữ nhé.")
    }

    @Test func emptyRecordingAsksAgain() async {
        speech.script = [Transcript(text: "", isFinal: true)]
        let vm = model()
        await vm.onAppear()
        #expect(vm.noticeKey == "conv.speech.empty")
        #expect(UserMessage(key: "conv.speech.empty").text == "Mình chưa nghe rõ. Bạn nói lại hoặc gõ chữ nhé.")
    }

    @Test func failedRetryKeepsPreviousText() async throws {
        let draft = TaskDraft(inputMode: .voice, originalInput: "Gọi cho mẹ")
        repo.save(draft)
        let vm = model(draftId: draft.id)
        await vm.onAppear()
        #expect(speech.startCount == 0)                                      // saved voice draft → transcript, no auto-listen
        #expect(api.parseCalls.isEmpty)                                      // and never auto-sent
        #expect(vm.mode == .transcript && vm.text == "Gọi cho mẹ")
        speech.script = [Transcript(text: "", isFinal: true)]
        await vm.speakAgain()
        #expect(vm.text == "Gọi cho mẹ")
        #expect(vm.noticeKey == "conv.speech.empty")
        #expect(repo.draft(draft.id)?.originalInput == "Gọi cho mẹ")         // never wiped (D-104)
    }

    @Test func sendNeedsTextAndNeverHappensAlone() async {
        speech.script = []
        let vm = model()
        await vm.onAppear()
        #expect(!vm.canSend)
        await vm.send()
        #expect(api.parseCalls.isEmpty)
        vm.text = "Gọi cho mẹ"
        #expect(vm.canSend)
        #expect(api.parseCalls.isEmpty)                                  // only "Gửi" sends
        await vm.send()
        #expect(api.parseCalls.count == 1)
        #expect(repo.draft(vm.draftId!)?.originalInput == "Gọi cho mẹ")
    }

    @Test func readAloudUsesSettingsRate() async {
        local.settings().speechRate = 0.4
        let vm = model()
        await vm.onAppear()
        await vm.toggleReading()
        #expect(tts.spoken.first?.text == "Nhắc tôi 8 giờ sáng mai uống thuốc")
        #expect(tts.spoken.first?.rate == 0.4)
    }

    // MARK: - Owner report 2026-11-10 + auto-stop (DOC-29)

    func fastModel() -> ConversationViewModel {
        ConversationViewModel(draftId: nil, repository: repo, speech: speech, api: api, tts: tts, localData: local,
                              silenceAfterSpeech: .milliseconds(50), noSpeechTimeout: .milliseconds(80))
    }

    @Test func emptyFinalAfterStopKeepsHeardWords() async {
        speech.script = [Transcript(text: "Gọi cho mẹ", isFinal: false), Transcript(text: "", isFinal: true)]
        let vm = model()
        await vm.onAppear()
        #expect(vm.text == "Gọi cho mẹ")
        #expect(vm.noticeKey == nil)
        #expect(repo.draft(vm.draftId!)?.originalInput == "Gọi cho mẹ")
    }

    @Test func silenceAfterSpeechStopsByItself() async {
        speech.script = [Transcript(text: "Gọi", isFinal: false), Transcript(text: "Gọi cho mẹ", isFinal: false)]
        speech.holdsUntilStop = true
        let vm = fastModel()
        await vm.onAppear()                                              // returns only after the auto-stop
        #expect(speech.stopCount == 1)
        #expect(vm.mode == .transcript)
        #expect(vm.text == "Gọi cho mẹ")
        #expect(vm.canSend)                                              // waits for "Gửi", never auto-sent
    }

    @Test func noSpeechStopsAndAsksAgain() async {
        speech.script = []
        speech.holdsUntilStop = true
        let vm = fastModel()
        await vm.onAppear()
        #expect(speech.stopCount == 1)
        #expect(vm.noticeKey == "conv.speech.empty")
    }

    // MARK: - 1B.4b working + unsupported (UI_SCREENS S03 modes 3 and 5)

    func typedModel(_ text: String) -> ConversationViewModel {
        let draft = TaskDraft(inputMode: .text, originalInput: text)
        repo.save(draft)
        return model(draftId: draft.id)
    }

    @Test func cancelWorkingKeepsText() {
        let vm = typedModel("Nhắc tôi uống thuốc")
        vm.showWorking()
        #expect(vm.mode == .working && !vm.canSend)
        vm.cancelWorking()
        #expect(vm.mode == .transcript)
        #expect(vm.text == "Nhắc tôi uống thuốc" && vm.canSend)
        #expect(UserMessage(key: "conv.working").text == "Mình đang soạn bản nháp…")
    }

    @Test func unsupportedShowsBackendSentenceAndRephrase() {
        let vm = typedModel("Nhắc tôi uống thuốc mỗi ngày")
        vm.showUnsupported(.init(reason: "recurringEvent", message: " Chưa hỗ trợ nhắc lặp lại mỗi ngày. "))
        #expect(vm.unsupportedMessage == "Chưa hỗ trợ nhắc lặp lại mỗi ngày.")
        #expect(vm.unsupportedAction == .rephrase)                      // oneTimeOffer hidden until 1B.13
        vm.rephrase()
        #expect(vm.mode == .transcript && vm.text == "Nhắc tôi uống thuốc mỗi ngày")
        #expect(repo.draft(vm.draftId!)?.steps.isEmpty == true)        // no steps built (spec §11)
    }

    @Test func bulkActionOpensCalendarToday() {
        let vm = typedModel("Xóa hết lịch tuần này")
        vm.showUnsupported(.init(reason: "bulkAction", message: "Chưa hỗ trợ xóa nhiều lịch cùng lúc."))
        #expect(vm.unsupportedAction == .openList(.calendarToday))     // D-280, DOC-30
        vm.showUnsupported(.init(reason: "other", message: "  "))
        #expect(vm.unsupportedMessage == nil)
    }

    @Test func parseFailedReturnsToTextWithMessage() {
        let vm = typedModel("abc")
        vm.showWorking()
        vm.showParseFailed()
        #expect(vm.mode == .transcript && vm.noticeKey == "conv.parseFailed")
        #expect(UserMessage(key: "conv.parseFailed").text == "Mình chưa hiểu yêu cầu. Bạn thử nói cách khác nhé.")
        #expect(UserMessage(key: "conv.unsupported.openList").text == "Mở danh sách để làm từng việc")
    }

    // MARK: - 1B.4c follow-up (UI_SCREENS S03 mode 4, spec §6.2 AC3, D-251)

    static let friday13 = ConversationViewModel.DateChip(fieldId: "startDate", value: "2026-11-13T09:00:00+07:00", label: "Thứ Sáu 13/11")
    static let friday20 = ConversationViewModel.DateChip(fieldId: "startDate", value: "2026-11-20T09:00:00+07:00", label: "Thứ Sáu 20/11")

    @Test func chipAnswersOnDeviceWithoutSending() {
        let vm = typedModel("Hẹn nha sĩ thứ Sáu 9 giờ")
        vm.showFollowUp(.init(question: "Bạn muốn hẹn thứ Sáu nào?", chips: [Self.friday13, Self.friday20]))
        #expect(!vm.canSendAnswer && !vm.canSend)
        vm.pick(Self.friday20)
        #expect(vm.lastAnswer == .chip(Self.friday20))                   // D-251: no parse, no unit
        vm.pick(.init(fieldId: "startDate", value: "x", label: "y"))     // not offered → ignored
        #expect(vm.lastAnswer == .chip(Self.friday20))
    }

    @Test func typedAnswerNeedsTextAndKeepsRequest() async {
        let vm = typedModel("Nhắc tôi uống thuốc")
        vm.showFollowUp(.init(question: "Bạn muốn được nhắc lúc mấy giờ?"))
        vm.answerText = "   "
        #expect(!vm.canSendAnswer)
        await vm.sendAnswer()
        #expect(vm.lastAnswer == nil)
        vm.answerText = " 8 giờ sáng mai "
        await vm.sendAnswer()
        #expect(vm.lastAnswer == .text("8 giờ sáng mai"))
        #expect(repo.draft(vm.draftId!)?.originalInput == "Nhắc tôi uống thuốc")   // request untouched
    }

    @Test func spokenAnswerFillsAnswerAndReturnsToQuestion() async {
        speech.script = [Transcript(text: "8 giờ sáng", isFinal: false), Transcript(text: "", isFinal: true)]
        let vm = typedModel("Nhắc tôi uống thuốc")
        let question = ConversationViewModel.FollowUp(question: "Bạn muốn được nhắc lúc mấy giờ?")
        vm.showFollowUp(question)
        await vm.listenForAnswer()
        #expect(vm.mode == .followUp(question))
        #expect(vm.answerText == "8 giờ sáng")
        #expect(vm.text == "Nhắc tôi uống thuốc")                         // the request is not replaced
        #expect(vm.canSendAnswer && vm.lastAnswer == nil)                 // never auto-sent
    }

    @Test func emptySpokenAnswerAsksAgainInPlace() async {
        speech.script = []
        let vm = typedModel("Gọi cho mẹ")
        let question = ConversationViewModel.FollowUp(question: "Bạn muốn gọi cho ai?")
        vm.showFollowUp(question)
        vm.answerText = "mẹ"
        await vm.listenForAnswer()
        #expect(vm.mode == .followUp(question))
        #expect(vm.answerText == "mẹ")                                    // previous answer kept
        #expect(vm.noticeKey == "conv.speech.empty")
    }

    @Test func skipOpensReviewOfThisDraft() {
        let vm = typedModel("Hẹn nha sĩ")
        #expect(vm.skipFollowUp() == nil)                                 // only in mode 4
        vm.showFollowUp(.init(question: "Lịch hẹn vào ngày nào, mấy giờ?"))
        #expect(vm.skipFollowUp() == vm.draftId)
        #expect(vm.lastAnswer == .skipped)
        #expect(UserMessage(key: "conv.followup.skip").text == "Bỏ qua, tôi sẽ sửa sau")
    }

    @Test func leavingStopsMicAndVoice() async {
        let vm = model()
        vm.onDisappear()
        await Task.yield()
        #expect(tts.stopCount == 1)
    }
}
