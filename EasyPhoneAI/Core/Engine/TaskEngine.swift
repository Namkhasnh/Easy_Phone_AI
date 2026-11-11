import Foundation
import os

/// ARCHITECTURE §5 — the **only** writer of `TaskStep` (D-123). Every state change goes through
/// `TaskStateMachine.transition`; every mutation is saved immediately (D-104).
@MainActor final class TaskEngine {
    static let historyCap = 50

    private let repository: any TaskRepository
    private let executors: [TaskKind: any StepExecutor]
    private let now: @MainActor () -> Date
    private let serviceIds: Set<String>
    private let resolver: DeviceResolver?
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "taskEngine")

    /// `nonisolated` so `AppEnvironment.mock()` (also the `@Entry` default) can build it off the main actor.
    nonisolated init(
        repository: any TaskRepository,
        executors: [TaskKind: any StepExecutor] = [:],   // one per kind, added in 1C / 1D
        serviceIds: Set<String> = [],                   // SupportedServices.json ids (1C.12)
        resolver: DeviceResolver? = nil,                // contacts / calendar lookups (1C.9)
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.resolver = resolver
        self.repository = repository
        self.executors = executors
        self.serviceIds = serviceIds
        self.now = now
    }

    // MARK: - Start from a device item (S11 "Sửa" / "Xóa")

    /// New draft with one update / delete step for `event`, saved and validated (→ `awaitingApproval` when complete).
    /// Nothing is executed until "Xác nhận" on S04 (D-100). Recurring events are refused (spec §6.4 AC5).
    func startDraft(from event: EventSummary, operation: TaskOperation,
                    timeZoneId: String = TimeZone.current.identifier) -> TaskDraft? {
        guard !event.isRecurring, operation == .update || operation == .delete else { return nil }
        // TODO(spec): S11 drafts have no spoken / typed input; `originalInput` stays empty, `inputMode = .text`.
        let draft = TaskDraft(inputMode: .text, originalInput: "", timeZoneId: timeZoneId,
                              steps: [DraftBuilder.step(from: event, operation: operation, timeZoneId: timeZoneId)])
        repository.save(draft)
        revalidate(stepId: draft.steps[0].id, in: draft)
        return draft
    }

    /// New draft with one step on an existing reminder (S12), saved and validated. Only `complete` may be confirmed
    /// right away by the caller (one tap, D-107); every other operation goes to S04 first (spec §6.5 AC3).
    func startDraft(from reminder: ReminderSummary, operation: TaskOperation, values: [String: String] = [:],
                    timeZoneId: String = TimeZone.current.identifier) -> TaskDraft? {
        guard !reminder.isRecurring, TaskKind.reminder.allowedOperations.contains(operation), operation != .create else {
            return nil
        }
        // TODO(spec): S12 drafts have no spoken / typed input; `originalInput` stays empty, `inputMode = .text`.
        let draft = TaskDraft(inputMode: .text, originalInput: "", timeZoneId: timeZoneId,
                              steps: [DraftBuilder.step(from: reminder, operation: operation, values: values,
                                                        timeZoneId: timeZoneId)])
        repository.save(draft)
        revalidate(stepId: draft.steps[0].id, in: draft)
        return draft
    }

    // MARK: - Confirm & execute (ARCHITECTURE §5.1)

    /// "Xác nhận" (D-100). Step 0 (permission explainer, D-185) is done by the ViewModel before calling this.
    func confirm(stepId: UUID, in draft: TaskDraft) async -> ConfirmResult {
        guard let index = draft.steps.firstIndex(where: { $0.id == stepId }) else { return .notAllowed }
        // 1. awaitingApproval + no validation issue (incl. ambiguity, D-106) + linked-step rule (§3.3).
        guard confirmBlocker(stepId: stepId, in: draft) == nil else { return .notAllowed }
        // 2. Store hash, attempt += 1, → processing, save before executing (applyInPlace + apply).
        guard apply(.userConfirmed, stepId: stepId, in: draft) else { return .notAllowed }
        let step = draft.steps[index]

        // 3. Recompute the hash right before executing (DATA_MODEL §3.4).
        guard ApprovalHash.matches(step) else {
            return finish(.failed(code: "approval.mismatch"), stepId: stepId, in: draft)
        }
        guard let executor = executors[step.kind] else {
            // TODO(spec): no executor for a kind (ride/food before Phase 3, or not built yet) has no error code.
            logger.warning("no executor for \(step.kind.rawValue, privacy: .public)")
            return finish(.failed(code: "unsupported"), stepId: stepId, in: draft)
        }
        // 4–6. Permission, idempotency and verification happen inside the executor.
        let outcome = await executor.execute(step, draft: draft)
        return finish(outcome, stepId: stepId, in: draft)
    }

    /// Why "Xác nhận" is disabled (UI_SCREENS S04), or nil when the step can be confirmed now.
    /// Order: ambiguity (D-106) → missing / invalid fields (§7.1) → previous linked step not done
    /// (DATA_MODEL §3.3: final, `handedOff` or `prepared`) → state is not `awaitingApproval`.
    func confirmBlocker(stepId: UUID, in draft: TaskDraft) -> ConfirmBlocker? {
        guard let step = draft.steps.first(where: { $0.id == stepId }) else { return .notConfirmable }
        let issues = Validator.validate(step, now: now(), serviceIds: serviceIds)
        if issues.contains(where: { $0.reason == .ambiguous }) { return .ambiguity }
        if !issues.isEmpty { return .missing }
        let previous = draft.steps.filter { $0.order < step.order }.max { $0.order < $1.order }
        if let previous, !(previous.state.isFinal || previous.state == .handedOff || previous.state == .prepared) {
            return .previousStep
        }
        return step.state == .awaitingApproval ? nil : .notConfirmable
    }

    /// SMS composer result (ARCHITECTURE §5.3, D-222). Only meaningful while the step is `processing`.
    @discardableResult
    func composerFinished(stepId: UUID, result: ComposerResult, in draft: TaskDraft) -> ConfirmResult {
        switch result {
        case .sent:
            return finish(.verified(evidence: "msg:sent:\(isoString(now(), timeZoneId: draft.timeZoneId))"),
                          stepId: stepId, in: draft)
        case .failed:
            // TODO(spec): no stable code for MessageUI `.failed`; `messages.sendFailed` used.
            return finish(.failed(code: "messages.sendFailed"), stepId: stepId, in: draft)
        case .cancelled:
            guard apply(.userCancelled, stepId: stepId, in: draft, context: .init(composerDismissed: true)),
                  let step = draft.steps.first(where: { $0.id == stepId }) else { return .notAllowed }
            return .finished(step.state)
        }
    }

    /// Maps an outcome to its event (§5.1) and writes the related fields.
    private func finish(_ outcome: ExecutionOutcome, stepId: UUID, in draft: TaskDraft) -> ConfirmResult {
        guard let index = draft.steps.firstIndex(where: { $0.id == stepId }) else { return .notAllowed }
        var step = draft.steps[index]
        let event: TaskEvent
        switch outcome {
        case let .verified(evidence):
            guard !evidence.isEmpty else {                                 // D-124: never succeeded without evidence
                // TODO(spec): no code for "executor returned empty evidence"; `evidence.missing` used.
                return finish(.failed(code: "evidence.missing"), stepId: stepId, in: draft)
            }
            step.resultEvidence = evidence
            event = .actionVerified
        case let .handedOff(note):
            step.handoffNote = note
            step.handoffPromptShown = false                                // D-242: ask once per hand-off
            event = .outcomeUnknownHandoff
        case .prepared:
            event = .dataPrepared
        case let .needsUI(effect):
            return .needsUI(effect)                                        // stays processing
        case let .failed(code):
            step.errorCode = code                                          // UI text = `error.<code>` (D-249)
            event = .actionFailed
        }
        guard applyInPlace(event, to: &step) else { return .notAllowed }
        draft.steps[index] = step
        save(draft)
        return .finished(step.state)
    }

    private func isoString(_ date: Date, timeZoneId: String) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: timeZoneId) ?? .current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
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

    // MARK: - Parse results (ARCHITECTURE §6.2, DATA_MODEL §6.2)

    /// First `/v1/parse` answer for `draft`: builds the steps (DraftBuilder), stores `serverRequestId` and the
    /// backend's `followUpQuestion` (D-281 decides later whether it is used), then validates each step →
    /// `needsInfo` / `awaitingApproval`. Saved once (D-104). Returns `false` (nothing changes) when the draft already
    /// has steps or the answer builds none (`unsupported`, or every step dropped) — the caller shows "Chưa hỗ trợ".
    @discardableResult
    func applyParsed(_ parsed: ParsedDraft, to draft: TaskDraft,
                     defaults: DraftBuilder.Defaults = .init()) -> Bool {
        guard draft.steps.isEmpty else {
            logger.warning("applyParsed: draft already has steps")
            return false
        }
        var steps = DraftBuilder.steps(from: parsed, now: now(), defaults: defaults)
        guard !steps.isEmpty else { return false }
        let llmTarget = FollowUpPlanner.llmTarget(of: steps)
        for i in steps.indices { revalidateInPlace(&steps[i]) }
        draft.steps = steps
        draft.serverRequestId = parsed.requestId
        setFollowUpWording(parsed.followUpQuestion, llmTarget: llmTarget, in: draft)
        save(draft)
        return true
    }

    /// DATA_MODEL §6.2 "run device resolution" for every step still open: contacts, calendar `targetRef`
    /// (ARCHITECTURE §5). Call after `applyParsed` / `mergeAnswer`. Saved once.
    func resolveDevice(in draft: TaskDraft) async {
        guard let resolver else { return }
        for step in draft.steps where DraftBuilder.mergeableStates.contains(step.state) {
            let resolution = await resolver.resolve(step, timeZoneId: draft.timeZoneId)
            guard !resolution.isEmpty else { continue }
            apply(resolution, stepId: step.id, in: draft)
        }
    }

    /// Writes a device resolution into one step (values + ambiguities + `targetRef`), then re-validates.
    /// Fields the user set (`source = .user`) are never overwritten.
    func apply(_ resolution: DeviceResolution, stepId: UUID, in draft: TaskDraft) {
        guard let index = draft.steps.firstIndex(where: { $0.id == stepId }),
              DraftBuilder.mergeableStates.contains(draft.steps[index].state) else { return }
        var step = draft.steps[index]
        for (id, value) in resolution.values {
            guard let f = step.fields.firstIndex(where: { $0.id == id }), step.fields[f].source != .user else { continue }
            step.fields[f].value = value
            step.fields[f].source = .device(origin: resolution.origin)
            step.fields[f].confidence = nil
            step.fields[f].ambiguity = nil
        }
        for (id, ambiguity) in resolution.ambiguities {
            guard let f = step.fields.firstIndex(where: { $0.id == id }) else { continue }
            step.fields[f].ambiguity = ambiguity
        }
        if let ref = resolution.targetRef { step.targetRef = ref }
        revalidateInPlace(&step)
        draft.steps[index] = step
        save(draft)
    }

    /// S06 pick (D-251: on device, no `/v1/parse`): the candidate becomes the field value as a user choice (ambiguity
    /// cleared, approval reset if any, D-101). Picking a contact also resolves its number (`phoneNumber` cleared first).
    func pick(_ candidateId: String, fieldId: String, stepId: UUID, in draft: TaskDraft) async {
        guard edit(fieldId: fieldId, value: candidateId, stepId: stepId, in: draft) else { return }
        guard fieldId == "contactId", let resolver,
              let index = draft.steps.firstIndex(where: { $0.id == stepId }) else { return }
        // The old contact's number no longer applies (unless the user typed one); `apply` re-validates and saves.
        if let f = draft.steps[index].fields.firstIndex(where: { $0.id == "phoneNumber" }),
           draft.steps[index].fields[f].source != .user {
            draft.steps[index].fields[f].value = nil
            draft.steps[index].fields[f].ambiguity = nil
            draft.steps[index].fields[f].source = .device(origin: "contacts")
        }
        let name = draft.steps[index].field("recipientName")?.value ?? ""
        apply(await resolver.numberResolution(contactId: candidateId, name: name), stepId: stepId, in: draft)
    }

    /// A contact chosen in the iOS contact picker (S06 "Chọn trong danh bạ", 1C.9c): `contactId` as a user choice and its
    /// numbers handed over by the picker (works without Contacts access). Old non-user number cleared first.
    func pickContact(id: String, displayName: String, phones: [PhoneEntry], stepId: UUID, in draft: TaskDraft) {
        guard edit(fieldId: "contactId", value: id, stepId: stepId, in: draft),
              let index = draft.steps.firstIndex(where: { $0.id == stepId }) else { return }
        if let f = draft.steps[index].fields.firstIndex(where: { $0.id == "phoneNumber" }),
           draft.steps[index].fields[f].source != .user {
            draft.steps[index].fields[f].value = nil
            draft.steps[index].fields[f].ambiguity = nil
            draft.steps[index].fields[f].source = .device(origin: "contacts")
        }
        var r = DeviceResolution(origin: "contacts")
        DeviceResolver.addNumber(from: phones, askingFor: displayName, into: &r)
        apply(r, stepId: stepId, in: draft)
    }

    /// S06 event pick for calendar update / delete (D-106, D-251): `targetRef` + the event's fields.
    func pickTarget(_ event: EventSummary, stepId: UUID, in draft: TaskDraft) {
        guard let step = draft.steps.first(where: { $0.id == stepId }),
              step.kind == .calendarEvent, step.operation == .update || step.operation == .delete else { return }
        apply(DeviceResolver.resolution(for: event, step: step, timeZoneId: draft.timeZoneId), stepId: stepId, in: draft)
    }

    /// The ONE question S03 asks next (D-281), or nil → open S04.
    func nextFollowUp(in draft: TaskDraft) -> FollowUpPrompt? {
        FollowUpPlanner.next(in: draft, now: now(), serviceIds: serviceIds)
    }

    /// D-281: keep the backend wording only when it targets the field the app asks about.
    private func setFollowUpWording(_ question: String?, llmTarget: FollowUpPlanner.Target?, in draft: TaskDraft) {
        let appTarget = FollowUpPlanner.target(in: draft, now: now(), serviceIds: serviceIds)
        draft.followUpQuestion = FollowUpPlanner.wording(question, llmTarget: llmTarget, appTarget: appTarget)
    }

    /// A typed / spoken follow-up answer (`/v1/parse` with `context`): merged without overwriting `.user` fields
    /// (API_CONTRACT §7.1 Example B), then re-validated. Saved once.
    func mergeAnswer(_ parsed: ParsedDraft, into draft: TaskDraft, defaults: DraftBuilder.Defaults = .init()) {
        var steps = DraftBuilder.merge(parsed, into: draft.steps, defaults: defaults)
        let llmTarget = FollowUpPlanner.llmTarget(of: steps.filter { DraftBuilder.mergeableStates.contains($0.state) })
        for i in steps.indices where DraftBuilder.mergeableStates.contains(steps[i].state) {
            revalidateInPlace(&steps[i])
        }
        draft.steps = steps
        draft.serverRequestId = parsed.requestId ?? draft.serverRequestId
        setFollowUpWording(parsed.followUpQuestion, llmTarget: llmTarget, in: draft)
        save(draft)
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

        if step.state == .succeeded { Self.turnIntoUpdate(&step) }  // D-290
        if step.state != .draft {
            guard applyInPlace(.userEdited, to: &step) else { return false }
        }
        revalidateInPlace(&step)
        draft.steps[index] = step
        // The backend wording was about the state before this edit (e.g. a chip pick, D-251); later questions use
        // the catalog text (D-281).
        draft.followUpQuestion = nil
        save(draft)
        return true
    }

    // MARK: - User actions without fields

    @discardableResult func cancel(stepId: UUID, in draft: TaskDraft) -> Bool { apply(.userCancelled, stepId: stepId, in: draft) }
    @discardableResult func retry(stepId: UUID, in draft: TaskDraft) -> Bool { apply(.retry, stepId: stepId, in: draft) }
    @discardableResult func markDone(stepId: UUID, in draft: TaskDraft) -> Bool { apply(.userMarkedDone, stepId: stepId, in: draft) }

    // MARK: - Internals

    static let editableStates: Set<TaskState> = [.draft, .needsInfo, .awaitingApproval, .succeeded]

    /// D-290: an edit after `succeeded` is a new action on the same item. Evidence is cleared; a calendar /
    /// reminder `create` becomes `update` on the identifier from its evidence (DATA_MODEL §3.5).
    static func turnIntoUpdate(_ step: inout TaskStep) {
        let evidence = step.resultEvidence
        step.resultEvidence = nil
        guard step.operation == .create, let evidence else { return }
        let prefix: String
        switch step.kind {
        case .calendarEvent: prefix = "ek:event:"
        case .reminder: prefix = "ek:reminder:"
        default: return
        }
        guard evidence.hasPrefix(prefix) else { return }
        step.operation = .update
        step.targetRef = String(evidence.dropFirst(prefix.count))
    }

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
            step.errorCode = nil                                      // a new attempt starts without the old error
            step.errorMessage = nil
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
