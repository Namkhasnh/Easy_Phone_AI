import Foundation

/// In-memory `TaskRepository` for previews and tests (D-206). Counts saves so tests can assert autosave (D-104).
@MainActor final class MockTaskRepository: TaskRepository {
    private(set) var drafts: [UUID: TaskDraft] = [:]
    private(set) var saveCount = 0

    /// `nonisolated` so `AppEnvironment.mock()` (also the `@Entry` default) can build it off the main actor.
    nonisolated init() {}

    convenience init(drafts: [TaskDraft]) {
        self.init()
        for d in drafts { self.drafts[d.id] = d }
    }

    func draft(_ id: UUID) -> TaskDraft? { drafts[id] }

    func save(_ draft: TaskDraft) {
        drafts[draft.id] = draft
        saveCount += 1
    }

    func steps(in states: Set<TaskState>) -> [(UUID, TaskStep)] {
        drafts.values.flatMap { d in d.steps.filter { states.contains($0.state) }.map { (d.id, $0) } }
    }

    func history(group: HistoryGroup) -> [TaskDraft] {
        drafts.values.filter { !$0.isArchived && $0.overallStatus == group }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteClosed() { drafts = drafts.filter { !$0.value.isClosed } }

    func wipeAll() { drafts = [:] }
}
