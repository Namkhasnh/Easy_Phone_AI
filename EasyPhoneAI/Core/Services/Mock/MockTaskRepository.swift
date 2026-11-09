import Foundation

/// In-memory `TaskRepository` for previews and tests (D-206). Counts saves so tests can assert autosave (D-104).
@MainActor final class MockTaskRepository: TaskRepository {
    private(set) var drafts: [UUID: TaskDraft] = [:]
    private(set) var saveCount = 0

    init(drafts: [TaskDraft] = []) {
        for d in drafts { self.drafts[d.id] = d }
    }

    func draft(_ id: UUID) -> TaskDraft? { drafts[id] }

    func save(_ draft: TaskDraft) {
        drafts[draft.id] = draft
        saveCount += 1
    }
}
