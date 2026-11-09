import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.8a — ARCHITECTURE §5 + DATA_MODEL §13 "Edit after approval clears hash and returns to `awaitingApproval`".
@MainActor
@Suite("TaskEngine core (ARCHITECTURE §5)")
struct TaskEngineTests {
    static let now = Validator.parseDateTime("2026-11-09T10:00:00+07:00")!
    static let future = "2026-11-10T08:00:00+07:00"

    let repo: MockTaskRepository
    let engine: TaskEngine

    init() {
        repo = MockTaskRepository()
        engine = TaskEngine(repository: repo, now: { Self.now })
    }

    func reminderDraft(title: String? = "Uống thuốc", due: String? = future) -> (TaskDraft, UUID) {
        let fields = FieldCatalog.mvp.fields(.reminder, .create).map {
            Field(id: $0.id, type: $0.type, value: ["title": title, "dueDate": due][$0.id] ?? nil, source: .ai,
                  confidence: 0.9)
        }
        let step = TaskStep(order: 0, kind: .reminder, operation: .create, fields: fields)
        return (TaskDraft(inputMode: .text, originalInput: "Nhắc tôi uống thuốc", steps: [step]), step.id)
    }

    // MARK: - revalidate

    @Test func completeDraftGoesToAwaitingApproval() {
        let (d, id) = reminderDraft()
        #expect(engine.revalidate(stepId: id, in: d) == [])
        #expect(d.steps[0].state == .awaitingApproval)
        #expect(d.steps[0].history.map(\.event) == [.allRequiredFilled])
        #expect(d.steps[0].fields.first { $0.id == "title" }?.required == true)
        #expect(repo.saveCount == 1)
    }

    @Test func incompleteDraftGoesToNeedsInfoThenEditFills() {
        let (d, id) = reminderDraft(due: nil)
        #expect(engine.revalidate(stepId: id, in: d).map(\.fieldId) == ["dueDate"])
        #expect(d.steps[0].state == .needsInfo)

        #expect(engine.edit(fieldId: "dueDate", value: Self.future, stepId: id, in: d))
        #expect(d.steps[0].state == .awaitingApproval)
        #expect(d.steps[0].history.map(\.event) == [.missingRequiredField, .userEdited, .allRequiredFilled])
    }

    @Test func revalidateInNeedsInfoWithIssuesIsSilent() {
        let (d, id) = reminderDraft(due: nil)
        engine.revalidate(stepId: id, in: d)
        let historyCount = d.steps[0].history.count
        engine.revalidate(stepId: id, in: d)                    // needsInfo + missing → no (illegal) event
        #expect(d.steps[0].state == .needsInfo)
        #expect(d.steps[0].history.count == historyCount)
    }

    // MARK: - edit (D-101, D-104, §1.7)

    @Test func editSetsUserSourceAndClearsConfidenceAndAmbiguity() {
        let (d, id) = reminderDraft()
        d.steps[0].fields[0].ambiguity = Ambiguity(kind: .other, question: "?", candidates: [])
        engine.edit(fieldId: "title", value: "Uống thuốc huyết áp", stepId: id, in: d)
        let f = d.steps[0].field("title")!
        #expect(f.value == "Uống thuốc huyết áp")
        #expect(f.source == .user)
        #expect(f.confidence == nil)
        #expect(f.ambiguity == nil)
        #expect(repo.saveCount == 1)
        #expect(d.updatedAt == Self.now)
    }

    @Test func editAfterApprovalClearsHashAndStaysAwaiting() {
        let (d, id) = reminderDraft()
        engine.revalidate(stepId: id, in: d)
        d.steps[0].approvedSnapshotHash = "stale"               // simulate a stored approval
        engine.edit(fieldId: "title", value: "Khác", stepId: id, in: d)
        #expect(d.steps[0].state == .awaitingApproval)
        #expect(d.steps[0].approvedSnapshotHash == nil)
        #expect(d.steps[0].history.last?.event == .userEdited)
    }

    @Test func clearingRequiredFieldInAwaitingGoesToNeedsInfo() {
        let (d, id) = reminderDraft()
        engine.revalidate(stepId: id, in: d)
        engine.edit(fieldId: "title", value: "", stepId: id, in: d)
        #expect(d.steps[0].field("title")?.value == nil)        // "" stored as empty
        #expect(d.steps[0].state == .needsInfo)
    }

    @Test func editAfterSuccessBecomesUpdateOnSameItem() {         // D-290
        let (d, id) = reminderDraft()
        d.steps[0].state = .succeeded                           // test setup only
        d.steps[0].resultEvidence = "ek:reminder:R-42"
        engine.edit(fieldId: "title", value: "Khác", stepId: id, in: d)
        let s = d.steps[0]
        #expect(s.state == .awaitingApproval)
        #expect(s.operation == .update)
        #expect(s.targetRef == "R-42")
        #expect(s.resultEvidence == nil)
    }

    @Test func turnIntoUpdateOnlyForCalendarAndReminderCreate() {
        var event = TaskStep(order: 0, kind: .calendarEvent, operation: .create, resultEvidence: "ek:event:E-1")
        TaskEngine.turnIntoUpdate(&event)
        #expect(event.operation == .update && event.targetRef == "E-1" && event.resultEvidence == nil)

        var sms = TaskStep(order: 0, kind: .sms, operation: .open, resultEvidence: "msg:sent:2026-11-09T10:00:00+07:00")
        TaskEngine.turnIntoUpdate(&sms)
        #expect(sms.operation == .open && sms.targetRef == nil && sms.resultEvidence == nil)

        var update = TaskStep(order: 0, kind: .calendarEvent, operation: .update, targetRef: "E-1",
                              resultEvidence: "ek:event:E-1")
        TaskEngine.turnIntoUpdate(&update)
        #expect(update.operation == .update && update.targetRef == "E-1" && update.resultEvidence == nil)
    }

    @Test(arguments: [TaskState.processing, .prepared, .handedOff, .failed, .unknown, .cancelled, .userMarkedDone])
    func editRefusedInOtherStates(_ state: TaskState) {
        let (d, id) = reminderDraft()
        d.steps[0].state = state                                // test setup only
        let before = d.steps[0]
        #expect(!engine.edit(fieldId: "title", value: "Khác", stepId: id, in: d))
        #expect(d.steps[0] == before)
        #expect(repo.saveCount == 0)
    }

    @Test func editUnknownFieldOrStepIsRefused() {
        let (d, id) = reminderDraft()
        #expect(!engine.edit(fieldId: "nope", value: "x", stepId: id, in: d))
        #expect(!engine.edit(fieldId: "title", value: "x", stepId: UUID(), in: d))
        #expect(repo.saveCount == 0)
    }

    // MARK: - apply (hash, attempt, history)

    @Test func confirmStoresHashAndIncrementsAttempt() {
        let (d, id) = reminderDraft()
        engine.revalidate(stepId: id, in: d)
        #expect(engine.apply(.userConfirmed, stepId: id, in: d))
        let s = d.steps[0]
        #expect(s.state == .processing)
        #expect(s.attempt == 1)
        #expect(s.approvedSnapshotHash == ApprovalHash.hash(s))
        #expect(ApprovalHash.matches(s))
    }

    @Test func retryClearsHashAndNextConfirmIsNewAttempt() {
        let (d, id) = reminderDraft()
        engine.revalidate(stepId: id, in: d)
        engine.apply(.userConfirmed, stepId: id, in: d)
        engine.apply(.actionFailed, stepId: id, in: d)
        #expect(engine.retry(stepId: id, in: d))
        #expect(d.steps[0].state == .awaitingApproval)
        #expect(d.steps[0].approvedSnapshotHash == nil)
        engine.apply(.userConfirmed, stepId: id, in: d)
        #expect(d.steps[0].attempt == 2)
    }

    @Test func illegalEventChangesNothing() {
        let (d, id) = reminderDraft()
        let before = d.steps[0]
        #expect(!engine.apply(.actionVerified, stepId: id, in: d))      // draft + actionVerified
        #expect(d.steps[0] == before)
        #expect(repo.saveCount == 0)
    }

    @Test func historyIsCappedAtFifty() {
        let (d, id) = reminderDraft()
        engine.revalidate(stepId: id, in: d)
        for i in 0..<60 { engine.edit(fieldId: "title", value: "T\(i)", stepId: id, in: d) }
        #expect(d.steps[0].history.count == TaskEngine.historyCap)
        #expect(d.steps[0].history.last?.event == .userEdited)
        #expect(d.steps[0].history.first?.event == .userEdited)          // oldest (allRequiredFilled) dropped
    }

    @Test func cancelAndMarkDone() {
        let (d, id) = reminderDraft()
        engine.revalidate(stepId: id, in: d)
        #expect(engine.cancel(stepId: id, in: d))
        #expect(d.steps[0].state == .cancelled)
        #expect(!engine.markDone(stepId: id, in: d))                      // closed state
    }
}
