import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.14a — D-281 follow-up rule (DATA_MODEL §13 row "Follow-up rule"), spec §6.2 AC3 / AC6, D-251 chip pick,
/// `context.currentDraft` without 🔒 fields (D-056).
@MainActor
@Suite("Follow-up planner (D-281)")
struct FollowUpPlannerTests {
    static let now = Validator.parseDateTime("2026-11-08T18:10:00+07:00")!
    static let friday = Validator.parseDateTime("2026-11-13T07:30:00+07:00")!

    let repo = MockTaskRepository()
    func engine(_ now: Date = now) -> TaskEngine { TaskEngine(repository: repo, now: { now }) }

    func applied(_ parsed: ParsedDraft, now: Date = now) -> (TaskDraft, TaskEngine) {
        let draft = TaskDraft(inputMode: .text, originalInput: "x")
        let engine = engine(now)
        #expect(engine.applyParsed(parsed, to: draft))
        return (draft, engine)
    }

    static func fixture(_ name: String) throws -> ParsedDraft { try DraftBuilderTests.parsed(name) }

    // MARK: - D-281

    @Test func backendWordingKeptWhenSameField() throws {
        let (draft, engine) = applied(try Self.fixture("missingTime"))
        let prompt = try #require(engine.nextFollowUp(in: draft))
        #expect(prompt.stepId == draft.steps[0].id && prompt.fieldId == "dueDate")
        #expect(prompt.question == "Bạn muốn được nhắc lúc mấy giờ?")
        #expect(prompt.candidates.isEmpty)
    }

    @Test func backendWordingForAnotherFieldReplacedByCatalogText() throws {
        // Every field filled → the LLM asked about nothing it can see, but `validate()` finds `startDate` in the past.
        var parsed = DraftBuilderTests.draft([DraftBuilderTests.step("calendarEvent", "create",
            [("title", "Khám răng"), ("startDate", "2026-11-01T09:00:00+07:00")])], followUp: "Bạn muốn ghi chú gì?")
        parsed.requestId = "req_x"
        let (draft, engine) = applied(parsed)
        #expect(draft.steps[0].state == .needsInfo)
        #expect(draft.followUpQuestion == nil)
        let prompt = try #require(engine.nextFollowUp(in: draft))
        #expect(prompt.fieldId == "startDate")
        #expect(prompt.question == "Lịch hẹn vào ngày nào, mấy giờ?")       // followup.calendarEvent.startDate
    }

    @Test func llmTargetIsFirstEmptyRequiredField() throws {
        let steps = DraftBuilder.steps(from: DraftBuilderTests.draft([DraftBuilderTests.step("reminder", "create",
            [("title", nil), ("dueDate", nil)])]), now: Self.now)
        #expect(FollowUpPlanner.llmTarget(of: steps)?.fieldId == "title")
        #expect(FollowUpPlanner.wording("  ", llmTarget: nil, appTarget: nil) == nil)
        let t = FollowUpPlanner.Target(stepId: steps[0].id, fieldId: "title")
        #expect(FollowUpPlanner.wording("Nhắc gì?", llmTarget: t, appTarget: t) == "Nhắc gì?")
        #expect(FollowUpPlanner.wording("Nhắc gì?", llmTarget: t,
                                        appTarget: .init(stepId: t.stepId, fieldId: "dueDate")) == nil)
    }

    @Test func questionWithoutIssueIgnored() throws {
        var parsed = try Self.fixture("followUpAnswer")
        parsed.followUpQuestion = "Bạn có muốn thêm ghi chú không?"
        let (draft, engine) = applied(parsed)
        #expect(draft.steps[0].state == .awaitingApproval)
        #expect(draft.followUpQuestion == nil)
        #expect(engine.nextFollowUp(in: draft) == nil)
    }

    // MARK: - Dates (AC6, D-251)

    @Test func ambiguousDateGivesChipsAndBackendWording() throws {
        let (draft, engine) = applied(try Self.fixture("ambiguousDate"), now: Self.friday)
        let prompt = try #require(engine.nextFollowUp(in: draft))
        #expect(prompt.fieldId == "startDate")
        #expect(prompt.question == "Bạn muốn hẹn thứ Sáu nào?")
        #expect(prompt.candidates.map(\.id) == ["2026-11-13T09:00:00+07:00", "2026-11-20T09:00:00+07:00"])
    }

    @Test func chipPickResolvesOnDeviceAndClearsWording() throws {
        let (draft, engine) = applied(try Self.fixture("ambiguousDate"), now: Self.friday)
        let prompt = try #require(engine.nextFollowUp(in: draft))
        #expect(engine.edit(fieldId: prompt.fieldId, value: prompt.candidates[1].id, stepId: prompt.stepId, in: draft))
        let field = try #require(draft.steps[0].field("startDate"))
        #expect(field.value == "2026-11-20T09:00:00+07:00" && field.source == .user && field.ambiguity == nil)
        #expect(draft.followUpQuestion == nil)
        #expect(draft.steps[0].state == .awaitingApproval)
        #expect(engine.nextFollowUp(in: draft) == nil)
    }

    @Test func ambiguityQuestionUsedWhenBackendGaveNone() throws {
        var parsed = try Self.fixture("ambiguousDate")
        parsed.followUpQuestion = nil
        let (draft, engine) = applied(parsed, now: Self.friday)
        #expect(engine.nextFollowUp(in: draft)?.question == "Bạn muốn chọn ngày nào?")   // ambiguity.date
    }

    // MARK: - What S03 can ask

    @Test func deviceOnlyFieldsAreNotAskedInS03() throws {
        let (draft, engine) = applied(try Self.fixture("sms"))
        #expect(draft.steps[0].state == .needsInfo)                          // contactId / phoneNumber missing (1C)
        #expect(engine.nextFollowUp(in: draft) == nil)                       // → S04
    }

    @Test func smsBodyAskedAfterSkippingContactFields() throws {
        let (draft, engine) = applied(DraftBuilderTests.draft([DraftBuilderTests.step("sms", "open",
            [("recipientName", "mẹ"), ("body", nil)])]))
        let prompt = try #require(engine.nextFollowUp(in: draft))
        #expect(prompt.fieldId == "body")
        #expect(prompt.question == "Bạn muốn nhắn nội dung gì?")
    }

    @Test func fieldWithoutOwnKeyUsesGenericText() throws {
        let (draft, engine) = applied(DraftBuilderTests.draft([DraftBuilderTests.step("place", "open",
            [("query", "chợ Bến Thành")])]))
        let prompt = try #require(engine.nextFollowUp(in: draft))
        #expect(prompt.fieldId == "name")
        let label = String(localized: String.LocalizationValue("field.place.name"))
        #expect(prompt.question == "Bạn cho mình biết thêm \(label) nhé?")
    }

    @Test func firstNeedsInfoStepByOrder() throws {
        let (draft, engine) = applied(DraftBuilderTests.draft([
            DraftBuilderTests.step("reminder", "create", [("title", "A"), ("dueDate", "2026-11-09T08:00:00+07:00")]),
            DraftBuilderTests.step("reminder", "create", [("title", "B"), ("dueDate", nil)]),
        ]))
        #expect(draft.steps.map(\.state) == [.awaitingApproval, .needsInfo])
        let prompt = try #require(engine.nextFollowUp(in: draft))
        #expect(prompt.stepId == draft.steps[1].id && prompt.fieldId == "dueDate")
        #expect(prompt.question == "Bạn muốn được nhắc lúc mấy giờ?")
    }

    // MARK: - currentDraft (D-056)

    @Test func wireDraftHasNoLockedFields() throws {
        let (draft, _) = applied(DraftBuilderTests.draft([
            DraftBuilderTests.step("sms", "open", [("recipientName", "mẹ"), ("body", "Con về muộn")]),
            DraftBuilderTests.step("reminder", "complete", [("title", "Uống thuốc")]),
        ]))
        let i = try #require(draft.steps[0].fields.firstIndex { $0.id == "contactId" })
        draft.steps[0].fields[i].value = "CN-123"                           // as DeviceResolver will (test only)
        let wire = DraftBuilder.wireDraft(draft)
        #expect(wire.steps[0].fields.map(\.id) == ["recipientName", "body", "channel"])
        #expect(wire.steps[1].fields.map(\.id) == ["title", "dueDate", "notes"])   // `completed` is app-built
        #expect(wire.requestId == "req_test")
        let json = String(decoding: try JSONEncoder().encode(wire), as: UTF8.self)
        for key in ["contactId", "phoneNumber", "CN-123", "targetRef", "resultEvidence", "calendarId", "completed"] {
            #expect(!json.contains(key), "\(key) leaked")
        }
    }

    @Test func wireDraftCarriesDateCandidates() throws {
        let (draft, _) = applied(try Self.fixture("ambiguousDate"), now: Self.friday)
        let wire = DraftBuilder.wireDraft(draft)
        let original = try Self.fixture("ambiguousDate")
        #expect(wire.steps[0].dateCandidates == original.steps[0].dateCandidates)
        #expect(wire.followUpQuestion == "Bạn muốn hẹn thứ Sáu nào?")
    }
}
