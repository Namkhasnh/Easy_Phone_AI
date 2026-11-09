import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.8b — ARCHITECTURE §5.1 (confirm flow), §5.3 (SMS composer, D-222), D-102, D-124, D-242.
@MainActor
@Suite("TaskEngine confirm (ARCHITECTURE §5.1)")
struct TaskEngineConfirmTests {
    static let now = Validator.parseDateTime("2026-11-09T10:00:00+07:00")!

    let repo = MockTaskRepository()

    func engine(_ executors: [TaskKind: any StepExecutor]) -> TaskEngine {
        TaskEngine(repository: repo, executors: executors, now: { Self.now })
    }

    /// A reminder step already in `awaitingApproval`.
    func readyReminder(_ engine: TaskEngine) -> (TaskDraft, UUID) {
        let fields = FieldCatalog.mvp.fields(.reminder, .create).map {
            Field(id: $0.id, type: $0.type, value: ["title": "Uống thuốc", "dueDate": "2026-11-10T08:00:00+07:00"][$0.id])
        }
        let step = TaskStep(order: 0, kind: .reminder, operation: .create, fields: fields)
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step])
        engine.revalidate(stepId: step.id, in: d)
        return (d, step.id)
    }

    func readySMS(_ engine: TaskEngine) -> (TaskDraft, UUID) {
        let values = ["recipientName": "anh Minh", "contactId": "C1", "phoneNumber": "+84901234567",
                      "body": "Em đến muộn", "channel": "sms"]
        let fields = FieldCatalog.mvp.fields(.sms, .open).map { Field(id: $0.id, type: $0.type, value: values[$0.id]) }
        let step = TaskStep(order: 0, kind: .sms, operation: .open, fields: fields)
        let d = TaskDraft(inputMode: .voice, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step])
        engine.revalidate(stepId: step.id, in: d)
        return (d, step.id)
    }

    @Test func verifiedOutcomeSucceedsWithEvidence() async {
        let exec = MockStepExecutor(outcome: .verified(evidence: "ek:reminder:R1"))
        let e = engine([.reminder: exec])
        let (d, id) = readyReminder(e)
        #expect(await e.confirm(stepId: id, in: d) == .finished(.succeeded))
        let s = d.steps[0]
        #expect(s.resultEvidence == "ek:reminder:R1")
        #expect(s.attempt == 1)
        #expect(s.history.map(\.event) == [.allRequiredFilled, .userConfirmed, .actionVerified])
        // The executor saw the step in `processing`, with the approval hash stored and saved first.
        #expect(exec.executed.count == 1)
        #expect(exec.executed[0].state == .processing)
        #expect(ApprovalHash.matches(exec.executed[0]))
    }

    @Test func savedBeforeExecuting() async {
        let exec = MockStepExecutor(outcome: .verified(evidence: "ek:reminder:R1"))
        let e = engine([.reminder: exec])
        let (d, id) = readyReminder(e)
        let before = repo.saveCount
        _ = await e.confirm(stepId: id, in: d)
        #expect(repo.saveCount == before + 2)                      // processing save + result save
    }

    @Test func emptyEvidenceNeverSucceeds() async {               // D-124
        let e = engine([.reminder: MockStepExecutor(outcome: .verified(evidence: ""))])
        let (d, id) = readyReminder(e)
        #expect(await e.confirm(stepId: id, in: d) == .finished(.failed))
        #expect(d.steps[0].errorCode == "evidence.missing")
    }

    @Test func handedOffSetsNoteAndPromptFlag() async {           // D-102, D-242
        let e = engine([.call: MockStepExecutor(outcome: .handedOff(note: "Cần hoàn tất cuộc gọi"))])
        let fields = FieldCatalog.mvp.fields(.call, .open).map {
            Field(id: $0.id, type: $0.type, value: ["recipientName": "0901234567", "phoneNumber": "+84901234567"][$0.id])
        }
        let step = TaskStep(order: 0, kind: .call, operation: .open, fields: fields, handoffPromptShown: true)
        let d = TaskDraft(inputMode: .text, originalInput: "x", steps: [step])
        e.revalidate(stepId: step.id, in: d)
        #expect(await e.confirm(stepId: step.id, in: d) == .finished(.handedOff))
        #expect(d.steps[0].handoffNote == "Cần hoàn tất cuộc gọi")
        #expect(d.steps[0].handoffPromptShown == false)
        #expect(d.steps[0].resultEvidence == nil)
    }

    @Test func failedOutcomeStoresCodeAndRetryClearsIt() async {
        let exec = MockStepExecutor(outcome: .failed(code: "permission.reminders.denied"))
        let e = engine([.reminder: exec])
        let (d, id) = readyReminder(e)
        #expect(await e.confirm(stepId: id, in: d) == .finished(.failed))
        #expect(d.steps[0].errorCode == "permission.reminders.denied")

        e.retry(stepId: id, in: d)
        exec.outcome = .verified(evidence: "ek:reminder:R1")
        #expect(await e.confirm(stepId: id, in: d) == .finished(.succeeded))
        #expect(d.steps[0].errorCode == nil)
        #expect(d.steps[0].attempt == 2)
    }

    @Test func notAllowedOutsideAwaitingApprovalOrWithIssues() async {
        let exec = MockStepExecutor(outcome: .verified(evidence: "ek:reminder:R1"))
        let e = engine([.reminder: exec])
        let (d, id) = readyReminder(e)
        e.edit(fieldId: "title", value: nil, stepId: id, in: d)      // → needsInfo
        #expect(await e.confirm(stepId: id, in: d) == .notAllowed)

        let (d2, id2) = readyReminder(e)
        d2.steps[0].fields[0].ambiguity = Ambiguity(kind: .other, question: "?", candidates: [])  // test setup only
        #expect(await e.confirm(stepId: id2, in: d2) == .notAllowed)
        #expect(d2.steps[0].state == .awaitingApproval)
        #expect(await e.confirm(stepId: UUID(), in: d2) == .notAllowed)
        #expect(exec.executed.isEmpty)
    }

    @Test func missingExecutorFails() async {
        let e = engine([:])
        let (d, id) = readyReminder(e)
        #expect(await e.confirm(stepId: id, in: d) == .finished(.failed))
        #expect(d.steps[0].errorCode == "unsupported")
    }

    // MARK: - SMS composer (§5.3, D-222)

    @Test func composerSentIsVerified() async {
        let effect = UIEffect.composer(recipients: ["+84901234567"], body: "Em đến muộn")
        let e = engine([.sms: MockStepExecutor(outcome: .needsUI(effect))])
        let (d, id) = readySMS(e)
        #expect(await e.confirm(stepId: id, in: d) == .needsUI(effect))
        #expect(d.steps[0].state == .processing)
        #expect(e.composerFinished(stepId: id, result: .sent, in: d) == .finished(.succeeded))
        #expect(d.steps[0].resultEvidence == "msg:sent:2026-11-09T10:00:00+07:00")
    }

    @Test func composerCancelledReturnsToApproval() async {
        let e = engine([.sms: MockStepExecutor(outcome: .needsUI(.composer(recipients: [], body: "")))])
        let (d, id) = readySMS(e)
        _ = await e.confirm(stepId: id, in: d)
        #expect(e.composerFinished(stepId: id, result: .cancelled, in: d) == .finished(.awaitingApproval))
        #expect(d.steps[0].approvedSnapshotHash == nil)
    }

    @Test func composerFailed() async {
        let e = engine([.sms: MockStepExecutor(outcome: .needsUI(.composer(recipients: [], body: "")))])
        let (d, id) = readySMS(e)
        _ = await e.confirm(stepId: id, in: d)
        #expect(e.composerFinished(stepId: id, result: .failed, in: d) == .finished(.failed))
        #expect(d.steps[0].errorCode == "messages.sendFailed")
    }

    @Test func composerResultIgnoredWhenNotProcessing() {
        let e = engine([:])
        let (d, id) = readySMS(e)
        #expect(e.composerFinished(stepId: id, result: .sent, in: d) == .notAllowed)
        #expect(d.steps[0].state == .awaitingApproval)
        #expect(d.steps[0].resultEvidence == nil)
    }
}
