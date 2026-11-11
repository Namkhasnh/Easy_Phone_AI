import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.14b — S03 parse loop (ARCHITECTURE §6.2, §9.2): "Gửi" → `/v1/parse` → draft → ONE question (D-281) / S04;
/// chip on device (D-251); typed answer → parse with `context` (no 🔒, D-056) → merge.
@MainActor
@Suite("Conversation parse loop (1B.14b)")
struct ConversationParseTests {
    static let evening = Validator.parseDateTime("2026-11-08T18:10:00+07:00")!
    static let friday = Validator.parseDateTime("2026-11-13T07:30:00+07:00")!

    let repo = MockTaskRepository()
    let speech = MockSpeechService()
    let local = MockLocalDataRepository()

    init() { local.settings().autoSend = false }                         // "Gửi" path; D-296 in ConversationTests

    static func fixture(_ name: String) throws -> ParsedDraft { try DraftBuilderTests.parsed(name) }

    func model(_ api: MockAPIClient, draft: TaskDraft, now: Date = evening) -> ConversationViewModel {
        repo.save(draft)
        let engine = TaskEngine(repository: repo, now: { now })
        return ConversationViewModel(draftId: draft.id, repository: repo, speech: speech, api: api, tts: MockTTSService(),
                                     localData: local, engine: engine, now: { now })
    }

    func typed(_ text: String) -> TaskDraft {
        TaskDraft(inputMode: .text, originalInput: text, timeZoneId: "Asia/Ho_Chi_Minh")
    }

    // MARK: - First parse

    @Test func typedRequestFromHomeIsParsedOnArrival() async throws {
        local.save(SavedPlace(label: "home", name: "Nhà", address: "1 Lê Lợi", latitude: 1, longitude: 2))
        local.save(SavedPlace(label: "custom", customLabel: "Nhà con gái", name: "X", address: "9 Hai Bà Trưng",
                              latitude: 1, longitude: 2))
        let api = MockAPIClient(parse: .success(try Self.fixture("missingTime")))
        let draft = typed("Nhắc tôi uống thuốc")
        let vm = model(api, draft: draft)
        await vm.onAppear()

        let call = try #require(api.parseCalls.first)
        #expect(api.parseCalls.count == 1)
        #expect(call.request.text == "Nhắc tôi uống thuốc" && call.request.inputMode == .text)
        #expect(call.request.now == "2026-11-08T18:10:00+07:00" && call.request.timezone == "Asia/Ho_Chi_Minh")
        #expect(call.request.context == .none)
        #expect(Set(call.request.savedPlaceLabels) == ["home", "custom"])          // labels only (DATA_MODEL §5)
        let body = String(decoding: try JSONEncoder().encode(call.request), as: UTF8.self)
        #expect(!body.contains("Lê Lợi") && !body.contains("Hai Bà Trưng"))

        #expect(vm.mode == .followUp(.init(question: "Bạn muốn được nhắc lúc mấy giờ?")))
        #expect(vm.prompt?.fieldId == "dueDate")
        #expect(draft.steps.first?.state == .needsInfo)
        #expect(vm.reviewDraftId == nil)
    }

    @Test func completeDraftOpensReview() async throws {
        let api = MockAPIClient(parse: .success(try Self.fixture("followUpAnswer")))
        let draft = typed("Nhắc tôi 8 giờ sáng mai uống thuốc")
        let vm = model(api, draft: draft)
        await vm.onAppear()
        #expect(vm.reviewDraftId == draft.id)
        #expect(draft.steps.first?.state == .awaitingApproval)
        #expect(draft.serverRequestId == "req_01JC8Z5B02")
    }

    @Test func unsupportedShowsModeFiveAndBuildsNothing() async throws {
        let api = MockAPIClient(parse: .success(try Self.fixture("unsupported")))
        let draft = typed("Nhắc tôi uống thuốc mỗi ngày")
        let vm = model(api, draft: draft)
        await vm.onAppear()
        guard case .unsupported(let u) = vm.mode else { Issue.record("mode \(vm.mode)"); return }
        #expect(u.reason == "recurringEvent")
        #expect(draft.steps.isEmpty)
    }

    @Test func everyStepDroppedIsUnsupported() async {
        let api = MockAPIClient(parse: .success(DraftBuilderTests.draft([DraftBuilderTests.step("ride", "open", [])])))
        let vm = model(api, draft: typed("Đặt xe về nhà"))
        await vm.onAppear()
        #expect(vm.mode == .unsupported(.init(reason: "other", message: nil)))
    }

    @Test func voiceDraftWaitsForGui() async throws {
        let api = MockAPIClient(parse: .success(try Self.fixture("missingTime")))
        let draft = TaskDraft(inputMode: .voice, originalInput: "Nhắc tôi uống thuốc")
        let vm = model(api, draft: draft)
        await vm.onAppear()
        #expect(api.parseCalls.isEmpty && vm.mode == .transcript)            // never auto-sent (API_CONTRACT §7.4)
        await vm.send()
        #expect(api.parseCalls.first?.request.inputMode == .voice)
        #expect(vm.prompt?.fieldId == "dueDate")
    }

    // MARK: - Errors (ARCHITECTURE §9.2)

    @Test(arguments: [
        (AppError.network(.offline), "error.network.offline"),
        (AppError.network(.timeout), "error.network.offline"),
        (AppError.api(code: "llm_invalid_output", retryable: false, details: nil, requestId: nil), "conv.parseFailed"),
        (AppError.api(code: "quota_exceeded", retryable: false, details: nil, requestId: nil), "error.quota_exceeded"),
        (AppError.api(code: "spend_cap", retryable: false, details: nil, requestId: nil), "error.spend_cap"),
        (AppError.api(code: "upstream_error", retryable: true, details: nil, requestId: nil), "error.upstream_error"),
        (AppError.decoding(requestId: nil), "error.generic"),
    ])
    func errorKeepsTextAndShowsNotice(error: AppError, key: String) async {
        let api = MockAPIClient(parse: .failure(error))
        let draft = typed("Nhắc tôi uống thuốc")
        let vm = model(api, draft: draft)
        await vm.onAppear()
        #expect(vm.mode == .transcript && vm.noticeKey == key)
        #expect(vm.text == "Nhắc tôi uống thuốc" && draft.originalInput == "Nhắc tôi uống thuốc")   // D-104
        #expect(draft.steps.isEmpty)
        #expect(!UserMessage(key: key).text.isEmpty && UserMessage(key: key).text != key)
        await vm.send()                                                       // "Thử lại" = new key
        #expect(api.parseCalls.count == 2 && api.parseCalls[0].key != api.parseCalls[1].key)
    }

    // MARK: - Follow-up answers

    @Test func typedAnswerIsSentWithContextAndMerged() async throws {
        let api = MockAPIClient(parseSequence: [.success(try Self.fixture("missingTime")),
                                                .success(try Self.fixture("followUpAnswer"))])
        let draft = typed("Nhắc tôi uống thuốc")
        let vm = model(api, draft: draft)
        await vm.onAppear()
        let stepId = try #require(draft.steps.first?.id)
        vm.answerText = "8 giờ sáng mai"
        await vm.sendAnswer()

        #expect(api.parseCalls.count == 2)
        let call = api.parseCalls[1]
        #expect(call.key != api.parseCalls[0].key)                           // one key per call (D-245)
        #expect(call.request.text == "8 giờ sáng mai" && call.request.inputMode == .text)
        #expect(call.request.context.draftId == draft.id)
        #expect(call.request.context.answeringFieldId == "dueDate")
        #expect(call.request.context.currentDraft?.steps.first?.fields.map(\.id) == ["title", "dueDate", "notes"])
        #expect(call.request.context.currentDraft?.requestId == "req_01JC8Z5A01")

        #expect(draft.steps.first?.id == stepId)                             // merged, not rebuilt
        #expect(draft.steps.first?.field("dueDate")?.value == "2026-11-09T08:00:00+07:00")
        #expect(draft.steps.first?.state == .awaitingApproval)
        #expect(vm.reviewDraftId == draft.id)
    }

    @Test func spokenAnswerIsSentAsVoice() async throws {
        let api = MockAPIClient(parseSequence: [.success(try Self.fixture("missingTime")),
                                                .success(try Self.fixture("followUpAnswer"))])
        let vm = model(api, draft: typed("Nhắc tôi uống thuốc"))
        await vm.onAppear()
        speech.script = [Transcript(text: "8 giờ sáng mai", isFinal: true)]
        await vm.listenForAnswer()
        #expect(api.parseCalls.count == 1)                                   // spoken answer waits for "Gửi"
        await vm.sendAnswer()
        #expect(api.parseCalls.last?.request.inputMode == .voice)
    }

    @Test func contextNeverCarriesLockedFields() async throws {
        let smsMissingBody = DraftBuilderTests.draft([DraftBuilderTests.step("sms", "open",
            [("recipientName", "mẹ"), ("body", nil)])])
        let api = MockAPIClient(parseSequence: [.success(smsMissingBody)])
        let draft = typed("Nhắn mẹ")
        let vm = model(api, draft: draft)
        await vm.onAppear()
        #expect(vm.prompt?.fieldId == "body")
        vm.answerText = "Con về muộn"
        await vm.sendAnswer()
        let body = String(decoding: try JSONEncoder().encode(api.parseCalls[1].request), as: UTF8.self)
        #expect(!body.contains("contactId") && !body.contains("phoneNumber"))  // D-056
    }

    @Test func unsupportedAnswerAsksTheSameQuestionAgain() async throws {
        let api = MockAPIClient(parseSequence: [.success(try Self.fixture("missingTime")),
                                                .success(try Self.fixture("unsupported"))])
        let draft = typed("Nhắc tôi uống thuốc")
        let vm = model(api, draft: draft)
        await vm.onAppear()
        let question = vm.mode
        vm.answerText = "mỗi ngày"
        await vm.sendAnswer()
        #expect(vm.mode == question && vm.noticeKey == "conv.parseFailed")
        #expect(draft.steps.count == 1 && draft.steps[0].state == .needsInfo)
    }

    @Test func answerErrorReturnsToQuestionKeepingAnswer() async throws {
        let api = MockAPIClient(parseSequence: [.success(try Self.fixture("missingTime")),
                                                .failure(.network(.offline))])
        let vm = model(api, draft: typed("Nhắc tôi uống thuốc"))
        await vm.onAppear()
        let question = vm.mode
        vm.answerText = "8 giờ sáng mai"
        await vm.sendAnswer()
        #expect(vm.mode == question && vm.noticeKey == "error.network.offline")
        #expect(vm.answerText == "8 giờ sáng mai" && vm.canSendAnswer)
    }

    // MARK: - Chips (D-251)

    @Test func chipPickResolvesOnDeviceWithoutParse() async throws {
        let api = MockAPIClient(parse: .success(try Self.fixture("ambiguousDate")))
        let draft = typed("Hẹn nha sĩ thứ Sáu 9 giờ")
        let vm = model(api, draft: draft, now: Self.friday)
        await vm.onAppear()
        guard case .followUp(let f) = vm.mode else { Issue.record("mode \(vm.mode)"); return }
        #expect(f.question == "Bạn muốn hẹn thứ Sáu nào?")
        #expect(f.chips.map(\.label) == ["Thứ Sáu 13/11 (hôm nay)", "Thứ Sáu 20/11"])
        vm.pick(f.chips[1])
        #expect(api.parseCalls.count == 1)                                   // no AI call, no unit
        #expect(draft.steps[0].field("startDate")?.value == "2026-11-20T09:00:00+07:00")
        #expect(draft.steps[0].field("startDate")?.source == .user)
        #expect(vm.reviewDraftId == draft.id)
    }

    // MARK: - Resume

    @Test func draftWithStepsResumesWithoutParse() async throws {
        let draft = typed("Nhắc tôi uống thuốc")
        let engine = TaskEngine(repository: repo, now: { Self.evening })
        engine.applyParsed(try Self.fixture("missingTime"), to: draft)
        let api = MockAPIClient()
        let vm = model(api, draft: draft)
        await vm.onAppear()
        #expect(api.parseCalls.isEmpty)
        #expect(vm.prompt?.fieldId == "dueDate")
    }
}
