import Foundation
import os

/// ARCHITECTURE §5 — the **only** writer of `TaskStep` (D-123). Every state change goes through
/// `TaskStateMachine.transition`; every mutation is saved immediately (D-104).
/// `confirm()` + executors (ARCHITECTURE §5.1, §5.3) come with 1A.8b.
@MainActor final class TaskEngine {
    static let historyCap = 50

    private let repository: any TaskRepository
    private let now: @MainActor () -> Date
    private let serviceIds: Set<String>
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "taskEngine")

    init(
        repository: any TaskRepository,
        serviceIds: Set<String> = [],                 // SupportedServices.json ids (1C.12)
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        self.serviceIds = serviceIds
        self.now = now
    }

    // MARK: - Events

    /// Applies one event to one step. Illegal transition → `false`, nothing changes (logged by the state machine).
    @discardableResult
    func apply(_ event: TaskEvent, stepId: UUID, in draft: TaskDraft,
               context: TransitionContext = .default) -> Bool {
        guard let index = draft.steps.firstIndex(where: { $0.id == stepId }) else {
            logger.warning("apply: unknown step \(stepId, privacy: .public)")
            return false
        }
        guard applyInPlace(event, to: &draft.steps[index], context: context) else { return false }
        save(draft)
        return true
    }

    /// Runs `Validator` and emits `allRequiredFilled` / `missingRequiredField` when the current state allows it
    /// (`draft`, `needsInfo`, `awaitingApproval`). Also recomputes `Field.required`. Returns the issues.
    @discardableResult
    func revalidate(stepId: UUID, in draft: TaskDraft) -> [ValidationIssue] {
        guard let index = draft.steps.firstIndex(where: { $0.id == stepId }) else { return [] }
        let issues = revalidateInPlace(&draft.steps[index])
        save(draft)
        return issues
    }

    // MARK: - Editing (D-101, D-104)

    /// Sets one field from a user edit: `source = .user`, `confidence = nil` (DATA_MODEL §1.7), ambiguity resolved
    /// (§2.1). Emits `userEdited` (approval reset, D-101) and re-validates. Returns `false` when the step's state
    /// does not accept edits (nothing changes).
    @discardableResult
    func edit(fieldId: String, value: String?, stepId: UUID, in draft: TaskDraft) -> Bool {
        guard let index = draft.steps.firstIndex(where: { $0.id == stepId }) else { return false }
        var step = draft.steps[index]
        // TODO(spec): DATA_MODEL §1.5 has no `userEdited` row for processing / prepared / handedOff / failed /
        // unknown / cancelled / userMarkedDone; edits there are refused (use "Thử lại" first).
        guard Self.editableStates.contains(step.state) else {
            logger.warning("edit refused in state \(step.state.rawValue, privacy: .public)")
            return false
        }
        guard let f = step.fields.firstIndex(where: { $0.id == fieldId }) else {
            logger.warning("edit: unknown field \(fieldId, privacy: .public)")
            return false
        }
        let normalized = value?.isEmpty == true ? nil : value
        step.fields[f].value = normalized
        step.fields[f].source = .user
        step.fields[f].confidence = nil
        step.fields[f].ambiguity = nil

        if step.state != .draft {
            // `succeeded` → `awaitingApproval` = a new update action (DATA_MODEL §1.5).
            // TODO(spec): switching `operation` to `.update` (+ `targetRef` from evidence) is not specified; 1C executors.
            guard applyInPlace(.userEdited, to: &step) else { return false }
        }
        revalidateInPlace(&step)
        draft.steps[index] = step
        save(draft)
        return true
    }

    // MARK: - User actions without fields

    @discardableResult func cancel(stepId: UUID, in draft: TaskDraft) -> Bool { apply(.userCancelled, stepId: stepId, in: draft) }
    @discardableResult func retry(stepId: UUID, in draft: TaskDraft) -> Bool { apply(.retry, stepId: stepId, in: draft) }
    @discardableResult func markDone(stepId: UUID, in draft: TaskDraft) -> Bool { apply(.userMarkedDone, stepId: stepId, in: draft) }

    // MARK: - Internals

    static let editableStates: Set<TaskState> = [.draft, .needsInfo, .awaitingApproval, .succeeded]

    /// The single place where `TaskStep.state` is written (D-123).
    private func applyInPlace(_ event: TaskEvent, to step: inout TaskStep,
                              context: TransitionContext = .default) -> Bool {
        let from = step.state
        guard let to = TaskStateMachine.transition(from, event, context: context) else { return false }
        let at = now()

        if event == .userConfirmed {
            step.approvedSnapshotHash = ApprovalHash.hash(step)       // DATA_MODEL §3.4: stored on userConfirmed
        }
        if to == .awaitingApproval {
            step.approvedSnapshotHash = nil                           // cleared whenever it enters awaitingApproval
        }
        if to == .processing {
            step.attempt += 1                                         // each processing entry (idempotency, D-105)
        }
        step.state = to
        step.stateChangedAt = at
        step.history.append(StateChange(from: from, to: to, event: event, at: at))
        if step.history.count > Self.historyCap {
            step.history.removeFirst(step.history.count - Self.historyCap)
        }
        return true
    }

    @discardableResult
    private func revalidateInPlace(_ step: inout TaskStep) -> [ValidationIssue] {
        step = Validator.applyRequired(step)
        let issues = Validator.validate(step, now: now(), serviceIds: serviceIds)
        switch (step.state, issues.isEmpty) {
        case (.draft, true), (.needsInfo, true): _ = applyInPlace(.allRequiredFilled, to: &step)
        case (.draft, false), (.awaitingApproval, false): _ = applyInPlace(.missingRequiredField, to: &step)
        default: break                                                // needsInfo + issues, awaitingApproval + ok, others
        }
        return issues
    }

    private func save(_ draft: TaskDraft) {
        draft.updatedAt = now()                                       // D-104
        repository.save(draft)
    }
}
