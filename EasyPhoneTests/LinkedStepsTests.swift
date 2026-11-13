import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.14 — DATA_MODEL §3.3 (D-120): linked fields follow their source, the linked step gets `userEdited` (D-101),
/// a user edit on the linked field breaks the link; step N+1 confirm waits for step N.
@MainActor
@Suite("Linked steps (DATA_MODEL §3.3)")
struct LinkedStepsTests {
    static let now = Validator.parseDateTime("2026-11-09T10:00:00+07:00")!
    static let future = "2026-11-10T08:00:00+07:00"

    let repo = MockTaskRepository()
    let engine: TaskEngine

    init() { engine = TaskEngine(repository: repo, now: { Self.now }) }

    func fields(_ kind: TaskKind, _ values: [String: String], linked: [String: (UUID, String)] = [:]) -> [Field] {
        FieldCatalog.mvp.fields(kind, .create).map { spec in
            let source: FieldSource = linked[spec.id].map { .linked(stepId: $0.0, fieldId: $0.1) } ?? .ai
            return Field(id: spec.id, type: spec.type, value: values[spec.id], source: source,
                         deviceOnly: spec.deviceOnly)
        }
    }

    /// Event (step 0) → reminder whose `title` follows the event title (step 1) → reminder whose `title`
    /// follows step 1's title (step 2, chain). All validated → `awaitingApproval`.
    func flow() -> TaskDraft {
        let event = TaskStep(order: 0, kind: .calendarEvent, operation: .create,
                             fields: fields(.calendarEvent, ["title": "Khám răng", "startDate": Self.future]))
        let first = TaskStep(order: 1, kind: .reminder, operation: .create,
                             fields: fields(.reminder, ["title": "Khám răng", "dueDate": Self.future],
                                            linked: ["title": (event.id, "title")]))
        let second = TaskStep(order: 2, kind: .reminder, operation: .create,
                              fields: fields(.reminder, ["title": "Khám răng", "dueDate": Self.future],
                                             linked: ["title": (first.id, "title")]))
        let d = TaskDraft(inputMode: .text, originalInput: "Đặt lịch khám răng", steps: [event, first, second])
        for step in d.steps { engine.revalidate(stepId: step.id, in: d) }
        return d
    }

    @Test func sourceEditUpdatesLinkedFieldsAlongTheChain() {
        let d = flow()
        #expect(d.steps.allSatisfy { $0.state == .awaitingApproval })
        #expect(engine.edit(fieldId: "title", value: "Khám mắt", stepId: d.steps[0].id, in: d))

        for i in 1...2 {
            #expect(d.steps[i].field("title")?.value == "Khám mắt")
            #expect(d.steps[i].history.last?.event == .userEdited)
            #expect(d.steps[i].state == .awaitingApproval)
            #expect(d.steps[i].approvedSnapshotHash == nil)
        }
        #expect(d.steps[1].field("title")?.source == .linked(stepId: d.steps[0].id, fieldId: "title"))
    }

    @Test func clearingTheSourceSendsLinkedStepToNeedsInfo() {
        let d = flow()
        engine.edit(fieldId: "title", value: nil, stepId: d.steps[0].id, in: d)
        #expect(d.steps[1].field("title")?.value == nil)
        #expect(d.steps[1].state == .needsInfo)
    }

    @Test func editingAnUnlinkedFieldLeavesOtherStepsAlone() {
        let d = flow()
        let before = d.steps[1].history.count
        engine.edit(fieldId: "location", value: "Nha khoa Kim", stepId: d.steps[0].id, in: d)
        #expect(d.steps[1].history.count == before)
    }

    @Test func userEditOnLinkedFieldBreaksTheLink() {
        let d = flow()
        engine.edit(fieldId: "title", value: "Mang sổ khám", stepId: d.steps[1].id, in: d)
        #expect(d.steps[1].field("title")?.source == .user)

        engine.edit(fieldId: "title", value: "Khám mắt", stepId: d.steps[0].id, in: d)
        #expect(d.steps[1].field("title")?.value == "Mang sổ khám")
        // Step 2 still follows step 1, which kept the user's value.
        #expect(d.steps[2].field("title")?.value == "Mang sổ khám")
    }

    @Test func linkedStepThatAlreadyRanIsNotChanged() {
        let d = flow()
        engine.apply(.userConfirmed, stepId: d.steps[1].id, in: d)          // → processing
        engine.edit(fieldId: "title", value: "Khám mắt", stepId: d.steps[0].id, in: d)
        #expect(d.steps[1].state == .processing)
        #expect(d.steps[1].field("title")?.value == "Khám răng")
    }

    @Test func nextStepConfirmWaitsForPreviousStep() {
        let d = flow()
        #expect(engine.confirmBlocker(stepId: d.steps[1].id, in: d) == .previousStep)
        #expect(engine.confirmBlocker(stepId: d.steps[0].id, in: d) == nil)
    }
}
