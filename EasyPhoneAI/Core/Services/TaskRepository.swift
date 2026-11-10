import Foundation

/// ARCHITECTURE §4.4. Persistence of `TaskDraft` (SwiftData main context, `@MainActor`, §8).
/// `save` = autosave (D-104): called by `TaskEngine` after every mutation.
@MainActor protocol TaskRepository: AnyObject, Sendable {
    func draft(_ id: UUID) -> TaskDraft?
    func save(_ draft: TaskDraft)
    /// Launch verification (ARCHITECTURE §5.4): every step in one of `states`, with its draft id.
    func steps(in states: Set<TaskState>) -> [(UUID, TaskStep)]
    /// S14: drafts of one group, not archived, newest `updatedAt` first.
    func history(group: HistoryGroup) -> [TaskDraft]
    /// "Xóa lịch sử": deletes only drafts whose steps are all closed (D-244).
    func deleteClosed()
    /// Account deletion / wipe (D-073).
    func wipeAll()
}
