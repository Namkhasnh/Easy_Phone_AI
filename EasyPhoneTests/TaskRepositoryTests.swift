import Foundation
import SwiftData
import Testing
@testable import EasyPhoneAI

/// 1A.9a — D-244, DATA_MODEL §3.2, §8, §13 "`currentStep`, History group, `isClosed` for drafts with
/// `failed` / `handedOff` / closed steps"; ARCHITECTURE §4.4 `TaskRepository`.
@Suite("TaskDraft status (D-244, DATA_MODEL §8)")
struct TaskDraftStatusTests {
    static func draft(_ states: [TaskState]) -> TaskDraft {
        let steps = states.enumerated().map { i, s in TaskStep(order: i, kind: .reminder, operation: .create, state: s) }
        return TaskDraft(inputMode: .text, originalInput: "x", steps: steps.reversed())   // order ≠ array order
    }

    @Test func groupPerState() {
        let expected: [TaskState: HistoryGroup] = [
            .draft: .needsYou, .needsInfo: .needsYou, .awaitingApproval: .needsYou, .prepared: .needsYou,
            .unknown: .needsYou, .failed: .needsYou, .processing: .waiting, .handedOff: .waiting,
            .succeeded: .done, .userMarkedDone: .done, .cancelled: .cancelled,
        ]
        #expect(Set(expected.keys) == Set(TaskState.allCases))
        for (state, group) in expected { #expect(state.historyGroup == group, "\(state)") }
        #expect(HistoryGroup.allCases.map(\.titleKey)
            == ["history.group.needsYou", "history.group.waiting", "history.group.done", "history.group.cancelled"])
    }

    @Test func currentStepSkipsClosedAndHandedOff() {
        let d = Self.draft([.succeeded, .handedOff, .awaitingApproval])
        #expect(d.currentStep?.order == 2)
        #expect(Self.draft([.failed, .awaitingApproval]).currentStep?.order == 0)       // failed is not closed
        #expect(Self.draft([.succeeded, .handedOff]).currentStep?.order == 1)           // none → last step
        #expect(Self.draft([]).currentStep == nil)
    }

    @Test func isClosedOnlyWhenEveryStepClosed() {
        #expect(Self.draft([.succeeded, .cancelled, .userMarkedDone]).isClosed)
        #expect(!Self.draft([.succeeded, .failed]).isClosed)
        #expect(!Self.draft([.succeeded, .handedOff]).isClosed)
        #expect(!Self.draft([.unknown]).isClosed)
        #expect(!Self.draft([]).isClosed)
    }

    @Test func overallStatusIsHighestPriority() {
        #expect(Self.draft([.succeeded, .handedOff]).overallStatus == .waiting)
        #expect(Self.draft([.handedOff, .failed]).overallStatus == .needsYou)
        #expect(Self.draft([.succeeded, .cancelled]).overallStatus == .done)
        #expect(Self.draft([.cancelled]).overallStatus == .cancelled)
        #expect(Self.draft([.succeeded, .handedOff]).isUnfinished)
        #expect(!Self.draft([.succeeded, .cancelled]).isUnfinished)
        #expect(Self.draft([.succeeded, .handedOff, .cancelled]).closedStepCount == 2)
    }
}

@MainActor
@Suite("LiveTaskRepository (SwiftData, in memory)")
struct LiveTaskRepositoryTests {
    let container: ModelContainer
    let repo: LiveTaskRepository

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        repo = LiveTaskRepository(container: container)
    }

    @Test func saveInsertsOnceAndFetchesById() throws {
        let d = TaskDraftStatusTests.draft([.awaitingApproval])
        repo.save(d)
        repo.save(d)                                                     // second save = update, not insert
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TaskDraft>()) == 1)
        #expect(repo.draft(d.id) === d)
        #expect(repo.draft(UUID()) == nil)
    }

    @Test func savedEditsSurviveAFreshContext() throws {
        let d = TaskDraftStatusTests.draft([.needsInfo])
        repo.save(d)
        d.steps[0].state = .awaitingApproval                             // test setup only
        repo.save(d)
        let fresh = ModelContext(container)
        let id = d.id
        let loaded = try fresh.fetch(FetchDescriptor<TaskDraft>(predicate: #Predicate { $0.id == id })).first
        #expect(loaded?.steps.first?.state == .awaitingApproval)
    }

    @Test func stepsInStates() {
        let a = TaskDraftStatusTests.draft([.processing, .awaitingApproval])
        let b = TaskDraftStatusTests.draft([.unknown])
        repo.save(a); repo.save(b)
        let found = repo.steps(in: [.processing, .unknown])
        #expect(found.count == 2)
        #expect(Set(found.map(\.0)) == [a.id, b.id])
        #expect(Set(found.map(\.1.state)) == [.processing, .unknown])
    }

    @Test func historyByGroupNewestFirstWithoutArchived() {
        let old = TaskDraftStatusTests.draft([.failed])
        old.updatedAt = .distantPast
        let new = TaskDraftStatusTests.draft([.awaitingApproval])
        let hidden = TaskDraftStatusTests.draft([.needsInfo])
        hidden.isArchived = true
        let done = TaskDraftStatusTests.draft([.succeeded])
        for d in [old, new, hidden, done] { repo.save(d) }
        #expect(repo.history(group: .needsYou).map(\.id) == [new.id, old.id])
        #expect(repo.history(group: .done).map(\.id) == [done.id])
        #expect(repo.history(group: .waiting).isEmpty)
    }

    @Test func deleteClosedKeepsFailedUnknownHandedOffAndOpen() {
        let closed = TaskDraftStatusTests.draft([.succeeded, .cancelled])
        let kept = [[TaskState.failed], [.unknown], [.succeeded, .handedOff], [.awaitingApproval]]
            .map(TaskDraftStatusTests.draft)
        repo.save(closed)
        kept.forEach(repo.save)
        repo.deleteClosed()
        #expect(repo.draft(closed.id) == nil)
        for d in kept { #expect(repo.draft(d.id) != nil) }
    }

    @Test func wipeAllDeletesEverything() throws {
        repo.save(TaskDraftStatusTests.draft([.awaitingApproval]))
        repo.save(TaskDraftStatusTests.draft([.succeeded]))
        repo.wipeAll()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TaskDraft>()) == 0)
    }

    @Test func engineAutosavesThroughLiveRepository() throws {
        let engine = TaskEngine(repository: repo)
        let fields = FieldCatalog.mvp.fields(.reminder, .create).map { Field(id: $0.id, type: $0.type) }
        let step = TaskStep(order: 0, kind: .reminder, operation: .create, fields: fields)
        let d = TaskDraft(inputMode: .text, originalInput: "x", steps: [step])
        engine.edit(fieldId: "title", value: "Uống thuốc", stepId: step.id, in: d)    // first edit inserts
        let id = d.id
        let loaded = try ModelContext(container).fetch(FetchDescriptor<TaskDraft>(predicate: #Predicate { $0.id == id }))
        #expect(loaded.first?.steps.first?.field("title")?.value == "Uống thuốc")   // D-104
    }
}
