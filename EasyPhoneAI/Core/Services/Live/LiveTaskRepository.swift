import Foundation
import os
import SwiftData

/// SwiftData `TaskRepository` on the container's main context (ARCHITECTURE §4.4, §8, P-28).
/// `steps` is a Codable composite attribute, so state filters run in memory after one fetch.
@MainActor final class LiveTaskRepository: TaskRepository {
    private let context: ModelContext
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "taskRepository")

    init(container: ModelContainer) {
        context = container.mainContext
    }

    func draft(_ id: UUID) -> TaskDraft? {
        var descriptor = FetchDescriptor<TaskDraft>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    func save(_ draft: TaskDraft) {
        if draft.modelContext == nil { context.insert(draft) }
        persist("save")
    }

    func steps(in states: Set<TaskState>) -> [(UUID, TaskStep)] {
        fetch(FetchDescriptor<TaskDraft>()).flatMap { d in
            d.steps.filter { states.contains($0.state) }.map { (d.id, $0) }
        }
    }

    func history(group: HistoryGroup) -> [TaskDraft] {
        let descriptor = FetchDescriptor<TaskDraft>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return fetch(descriptor).filter { $0.overallStatus == group }
    }

    func deleteClosed() {
        for d in fetch(FetchDescriptor<TaskDraft>()) where d.isClosed { context.delete(d) }
        persist("deleteClosed")
    }

    func wipeAll() {
        do { try context.delete(model: TaskDraft.self) } catch { logFailure("wipeAll", error) }
        persist("wipeAll")
    }

    // MARK: - Private

    private func fetch(_ descriptor: FetchDescriptor<TaskDraft>) -> [TaskDraft] {
        do { return try context.fetch(descriptor) } catch {
            logFailure("fetch", error)
            return []
        }
    }

    private func persist(_ op: String) {
        // TODO(spec): a failed SwiftData save has no UI (D-104); the change stays in the context and is retried
        // on the next save.
        do { try context.save() } catch { logFailure(op, error) }
    }

    private func logFailure(_ op: String, _ error: any Error) {
        // D-059 spirit: log the operation and error type only, never draft content.
        logger.error("\(op, privacy: .public) failed: \(String(describing: type(of: error)), privacy: .public)")
    }
}
