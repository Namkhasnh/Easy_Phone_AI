import Foundation

/// ARCHITECTURE §4.4. Persistence of `TaskDraft` (SwiftData main context, `@MainActor`, §8).
/// `save` = autosave (D-104): called by `TaskEngine` after every mutation.
// TODO(spec): only `draft` / `save` so far; `steps(in:)`, `history(group:)`, `deleteClosed()`, `wipeAll()`
// and the SwiftData `LiveTaskRepository` come with 1A.9.
@MainActor protocol TaskRepository: AnyObject {
    func draft(_ id: UUID) -> TaskDraft?
    func save(_ draft: TaskDraft)
}
