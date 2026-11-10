import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.13 — ARCHITECTURE §5 `DraftBuilder`, DATA_MODEL §6.2 "App mapping", API_CONTRACT §7.1 Example B (merge).
/// Uses the shared contract fixtures (`parse.*.response.json`).
@MainActor
@Suite("DraftBuilder (DATA_MODEL §6.2)")
struct DraftBuilderTests {
    /// Example B is said at 2026-11-08 18:10 (+07:00).
    static let now = Validator.parseDateTime("2026-11-08T18:10:00+07:00")!

    let repo = MockTaskRepository()
    var engine: TaskEngine { TaskEngine(repository: repo, now: { Self.now }) }

    static func parsed(_ name: String) throws -> ParsedDraft {
        try ContractFixtureTests.decode(ParsedDraft.self, "parse.\(name).response.json")
    }

    static func step(_ kind: String, _ op: String, _ fields: [(String, String?)],
                     candidates: [ParsedDateCandidate] = []) -> ParsedStep {
        ParsedStep(kind: kind, operation: op,
                   fields: fields.map { ParsedField(id: $0.0, value: $0.1, confidence: $0.1 == nil ? nil : 0.9,
                                                    sourceQuote: nil) },
                   dateCandidates: candidates)
    }

    static func draft(_ steps: [ParsedStep], followUp: String? = nil) -> ParsedDraft {
        ParsedDraft(schemaVersion: 1, requestId: "req_test", steps: steps, followUpQuestion: followUp, unsupported: nil)
    }

    // MARK: - Build

    @Test func smsFixtureBuildsCatalogOrderedAIStep() throws {
        let steps = DraftBuilder.steps(from: try Self.parsed("sms"), now: Self.now)
        let step = try #require(steps.first)
        #expect(steps.count == 1)
        #expect(step.kind == .sms && step.operation == .open && step.state == .draft && step.order == 0)
        #expect(step.fields.map(\.id) == FieldCatalog.mvp.fields(.sms, .open).map(\.id))   // catalog order
        #expect(step.field("recipientName")?.value == "anh Minh")
        #expect(step.field("recipientName")?.source == .ai)
        #expect(step.field("recipientName")?.confidence == 0.95)
        #expect(step.field("channel")?.value == "sms")
        // 🔒 fields exist, empty, device-only; required per D-247 / D-253 (channel = sms, name is not a number).
        #expect(step.field("contactId")?.deviceOnly == true)
        #expect(step.field("contactId")?.value == nil)
        #expect(step.field("phoneNumber")?.required == true)
        #expect(step.field("contactId")?.required == true)
        #expect(step.history.isEmpty)
    }

    @Test func newUUIDsEveryBuild() throws {
        let p = try Self.parsed("sms")
        let a = DraftBuilder.steps(from: p, now: Self.now)[0].id
        let b = DraftBuilder.steps(from: p, now: Self.now)[0].id
        #expect(a != b)
    }

    @Test func catalogDefaultsFilled() {
        let p = Self.draft([
            Self.step("calendarEvent", "create", [("title", "Khám răng"), ("startDate", "2026-11-09T14:00:00+07:00")]),
            Self.step("sms", "open", [("recipientName", "mẹ"), ("body", "Con về muộn")]),
            Self.step("place", "open", [("query", "bệnh viện")]),
        ])
        let steps = DraftBuilder.steps(from: p, now: Self.now, defaults: .init(mapsApp: "googleMaps", dateQuestion: "q"))
        #expect(steps.map(\.order) == [0, 1, 2])
        #expect(steps[0].field("allDay")?.value == "false")
        #expect(steps[0].field("alertMinutesBefore")?.value == "60")
        #expect(steps[0].field("alertMinutesBefore")?.confidence == nil)     // default → no needsReview
        #expect(steps[0].field("alertMinutesBefore")?.needsReview == false)
        #expect(steps[0].field("endDate")?.value == nil)                     // not filled (TODO(spec), 1C)
        #expect(steps[1].field("channel")?.value == "sms")
        #expect(steps[2].field("mapsApp")?.value == "googleMaps")
    }

    @Test func llmValueBeatsDefault() {
        let p = Self.draft([Self.step("calendarEvent", "create", [("title", "Họp"), ("alertMinutesBefore", "15")])])
        #expect(DraftBuilder.steps(from: p, now: Self.now)[0].field("alertMinutesBefore")?.value == "15")
    }

    @Test func unknownKindsOperationsAndFieldsDropped() {
        let p = Self.draft([
            Self.step("ride", "open", [("destination", "nhà")]),            // Phase 3: not in the MVP catalog (D-150)
            Self.step("reminder", "open", [("title", "x")]),                // invalid pair (§1.2)
            Self.step("teleport", "create", []),                            // unknown kind
            Self.step("call", "open", [("recipientName", "mẹ"), ("contactId", "ABC"), ("phoneNumber", "+84901234567"),
                                       ("nickname", "x")]),
        ])
        let steps = DraftBuilder.steps(from: p, now: Self.now)
        #expect(steps.count == 1)
        #expect(steps[0].kind == .call && steps[0].order == 0)
        #expect(steps[0].field("contactId")?.value == nil)                  // 🔒 never from the LLM (D-056)
        #expect(steps[0].field("phoneNumber")?.value == nil)
        #expect(steps[0].field("nickname") == nil)
    }

    @Test func reminderCompleteIsAppBuiltTrue() {
        let p = Self.draft([Self.step("reminder", "complete", [("title", "Uống thuốc"), ("completed", "false")])])
        let step = DraftBuilder.steps(from: p, now: Self.now)[0]
        #expect(step.field("completed")?.value == "true")                   // D-248: LLM value ignored
    }

    @Test func blankValuesBecomeNilAndTrimmed() {
        let p = Self.draft([Self.step("reminder", "create", [("title", "  Uống thuốc \n"), ("dueDate", "  ")])])
        let step = DraftBuilder.steps(from: p, now: Self.now)[0]
        #expect(step.field("title")?.value == "Uống thuốc")
        #expect(step.field("dueDate")?.value == nil)
        #expect(step.field("dueDate")?.confidence == nil)
    }

    @Test func unsupportedBuildsNothing() throws {
        #expect(DraftBuilder.steps(from: try Self.parsed("unsupported"), now: Self.now).isEmpty)
    }

    @Test func dateCandidatesBecomeDateAmbiguity() throws {
        let step = DraftBuilder.steps(from: try Self.parsed("ambiguousDate"), now: Self.now,
                                      defaults: .init(dateQuestion: "Bạn muốn chọn ngày nào?"))[0]
        let field = try #require(step.field("startDate"))
        let ambiguity = try #require(field.ambiguity)
        #expect(field.value == nil)                                         // never auto-picked (D-106)
        #expect(ambiguity.kind == .date)
        #expect(ambiguity.question == "Bạn muốn chọn ngày nào?")
        #expect(ambiguity.candidates.map(\.id) == ["2026-11-13T09:00:00+07:00", "2026-11-20T09:00:00+07:00"])
        #expect(ambiguity.candidates.map(\.title) == ["Thứ Sáu 13/11 (hôm nay)", "Thứ Sáu 20/11"])
        #expect(step.field("title")?.ambiguity == nil)
    }

    @Test func singleCandidateStillAsks() {
        let c = ParsedDateCandidate(fieldId: "dueDate", value: "2026-11-09T08:00:00+07:00", label: "Thứ Hai 9/11")
        let bad = ParsedDateCandidate(fieldId: "dueDate", value: "mai", label: "?")
        let other = ParsedDateCandidate(fieldId: "title", value: "2026-11-09T08:00:00+07:00", label: "x")
        let p = Self.draft([Self.step("reminder", "create", [("title", "x"), ("dueDate", nil)],
                                      candidates: [c, bad, other])])
        let step = DraftBuilder.steps(from: p, now: Self.now)[0]
        #expect(step.field("dueDate")?.ambiguity?.candidates.map(\.id) == [c.value])
        #expect(step.field("title")?.ambiguity == nil)
    }

    @Test func defaultQuestionIsTheLocalizedKey() {
        #expect(DraftBuilder.Defaults().dateQuestion == "Bạn muốn chọn ngày nào?")
    }

    // MARK: - Engine: applyParsed → validate (DATA_MODEL §6.2 last line)

    @Test func applyParsedCompleteGoesToAwaitingApproval() throws {
        let draft = TaskDraft(inputMode: .text, originalInput: "Nhắc tôi 8 giờ sáng mai uống thuốc")
        #expect(engine.applyParsed(try Self.parsed("followUpAnswer"), to: draft))
        #expect(draft.steps.count == 1)
        #expect(draft.steps[0].state == .awaitingApproval)
        #expect(draft.steps[0].history.map(\.event) == [.allRequiredFilled])
        #expect(draft.serverRequestId == "req_01JC8Z5B02")
        #expect(draft.followUpQuestion == nil)
        #expect(repo.saveCount == 1)
    }

    @Test func applyParsedMissingGoesToNeedsInfo() throws {
        let draft = TaskDraft(inputMode: .text, originalInput: "Nhắc tôi uống thuốc")
        #expect(engine.applyParsed(try Self.parsed("missingTime"), to: draft))
        #expect(draft.steps[0].state == .needsInfo)
        #expect(draft.steps[0].history.map(\.event) == [.missingRequiredField])
        #expect(draft.followUpQuestion == "Bạn muốn được nhắc lúc mấy giờ?")  // kept; D-281 decides in 1B.14
    }

    @Test func applyParsedAmbiguousDateNeedsInfo() throws {
        let draft = TaskDraft(inputMode: .text, originalInput: "Hẹn nha sĩ thứ Sáu 9 giờ")
        let engine = TaskEngine(repository: repo, now: { Validator.parseDateTime("2026-11-13T07:30:00+07:00")! })
        #expect(engine.applyParsed(try Self.parsed("ambiguousDate"), to: draft))
        #expect(draft.steps[0].state == .needsInfo)
    }

    @Test func applyParsedRefusesUnsupportedAndFilledDrafts() throws {
        let empty = TaskDraft(inputMode: .text, originalInput: "x")
        #expect(engine.applyParsed(try Self.parsed("unsupported"), to: empty) == false)
        #expect(empty.steps.isEmpty)
        #expect(repo.saveCount == 0)

        let filled = TaskDraft(inputMode: .text, originalInput: "x")
        #expect(engine.applyParsed(try Self.parsed("sms"), to: filled))
        let id = filled.steps[0].id
        #expect(engine.applyParsed(try Self.parsed("missingTime"), to: filled) == false)
        #expect(filled.steps.map(\.id) == [id])
    }

    // MARK: - Merge (API_CONTRACT §7.1 Example B)

    @Test func exampleBMergeFillsDueDateAndApproves() throws {
        let draft = TaskDraft(inputMode: .text, originalInput: "Nhắc tôi uống thuốc")
        engine.applyParsed(try Self.parsed("missingTime"), to: draft)
        let stepId = draft.steps[0].id
        engine.mergeAnswer(try Self.parsed("followUpAnswer"), into: draft)
        let step = draft.steps[0]
        #expect(step.id == stepId)                                         // same step, not rebuilt
        #expect(step.field("dueDate")?.value == "2026-11-09T08:00:00+07:00")
        #expect(step.field("dueDate")?.confidence == 0.95)
        #expect(step.field("dueDate")?.source == .ai)
        #expect(step.state == .awaitingApproval)
        #expect(step.history.map(\.event) == [.missingRequiredField, .allRequiredFilled])
        #expect(draft.followUpQuestion == nil)
        #expect(draft.serverRequestId == "req_01JC8Z5B02")
    }

    @Test func mergeKeepsUserFields() throws {
        let draft = TaskDraft(inputMode: .text, originalInput: "Nhắc tôi uống thuốc")
        engine.applyParsed(try Self.parsed("missingTime"), to: draft)
        let id = draft.steps[0].id
        engine.edit(fieldId: "title", value: "Uống thuốc huyết áp", stepId: id, in: draft)
        let answer = Self.draft([Self.step("reminder", "create",
                                           [("title", "Uống thuốc"), ("dueDate", "2026-11-09T08:00:00+07:00")])])
        engine.mergeAnswer(answer, into: draft)
        #expect(draft.steps[0].field("title")?.value == "Uống thuốc huyết áp")
        #expect(draft.steps[0].field("title")?.source == .user)
        #expect(draft.steps[0].field("dueDate")?.value == "2026-11-09T08:00:00+07:00")
        #expect(draft.steps[0].state == .awaitingApproval)
    }

    @Test func mergeUnchangedValueKeepsConfidenceAndNullKeepsOldValue() {
        let first = Self.draft([Self.step("calendarEvent", "create",
                                          [("title", "Khám răng"), ("location", "Nha khoa ABC"), ("startDate", nil)])])
        var steps = DraftBuilder.steps(from: first, now: Self.now)
        let answer = Self.draft([ParsedStep(kind: "calendarEvent", operation: "create", fields: [
            ParsedField(id: "title", value: "Khám răng", confidence: 0.5, sourceQuote: nil),
            ParsedField(id: "location", value: nil, confidence: nil, sourceQuote: nil),
            ParsedField(id: "startDate", value: "2026-11-09T14:00:00+07:00", confidence: 0.8, sourceQuote: nil),
        ], dateCandidates: [])])
        steps = DraftBuilder.merge(answer, into: steps)
        #expect(steps[0].field("title")?.confidence == 0.9)                // unchanged → not updated
        #expect(steps[0].field("location")?.value == "Nha khoa ABC")       // null → kept
        #expect(steps[0].field("startDate")?.value == "2026-11-09T14:00:00+07:00")
    }

    @Test func mergeNeverTouchesStepsThatRan() {
        let first = Self.draft([Self.step("reminder", "create", [("title", "A"), ("dueDate", "2026-11-09T08:00:00+07:00")])])
        var steps = DraftBuilder.steps(from: first, now: Self.now)
        steps[0].state = .succeeded                                         // test fixture only, not via the engine
        let answer = Self.draft([Self.step("reminder", "create", [("title", "B"), ("dueDate", nil)])])
        #expect(DraftBuilder.merge(answer, into: steps) == steps)
    }

    @Test func mergeSkipsDifferentKindAndExtraSteps() {
        let first = Self.draft([Self.step("reminder", "create", [("title", "A"), ("dueDate", nil)])])
        let steps = DraftBuilder.steps(from: first, now: Self.now)
        let answer = Self.draft([
            Self.step("calendarEvent", "create", [("title", "B")]),
            Self.step("reminder", "create", [("title", "C")]),
        ])
        #expect(DraftBuilder.merge(answer, into: steps) == steps)
    }

    @Test func mergeDateCandidatesReplaceAndResolve() {
        let c1 = ParsedDateCandidate(fieldId: "startDate", value: "2026-11-13T09:00:00+07:00", label: "Thứ Sáu 13/11")
        let first = Self.draft([Self.step("calendarEvent", "create", [("title", "Hẹn"), ("startDate", nil)],
                                          candidates: [c1])])
        var steps = DraftBuilder.steps(from: first, now: Self.now)
        #expect(steps[0].field("startDate")?.ambiguity != nil)
        // Answer still unclear → candidates stay (empty value); answer with a value → ambiguity cleared.
        steps = DraftBuilder.merge(Self.draft([Self.step("calendarEvent", "create", [("startDate", nil)])]), into: steps)
        #expect(steps[0].field("startDate")?.ambiguity?.candidates.map(\.id) == [c1.value])
        steps = DraftBuilder.merge(Self.draft([Self.step("calendarEvent", "create",
                                                         [("startDate", "2026-11-20T09:00:00+07:00")])]), into: steps)
        #expect(steps[0].field("startDate")?.ambiguity == nil)
        #expect(steps[0].field("startDate")?.value == "2026-11-20T09:00:00+07:00")
    }

    @Test func mergeUnsupportedChangesNothing() throws {
        let steps = DraftBuilder.steps(from: try Self.parsed("missingTime"), now: Self.now)
        #expect(DraftBuilder.merge(try Self.parsed("unsupported"), into: steps) == steps)
    }
}
