import Foundation
import Observation

/// S04 Review (UI_SCREENS S04, spec §5.3, ARCHITECTURE §2.1). Forwards intents to `TaskEngine`; no business rules.
/// Holds the `@Model` draft itself (observable) instead of a value snapshot so edits made by the engine show at once.
@Observable @MainActor final class ReviewViewModel {
    private(set) var draft: TaskDraft?
    private(set) var stepId: UUID?
    /// Field whose editor (S05, 1A.12) should open.
    var editingFieldId: String?
    /// Set after "Hủy" / "Để sau": the View pops back.
    private(set) var didClose = false
    /// Set after "Xong": the View returns to Home (S02).
    private(set) var didFinish = false

    private let engine: TaskEngine
    private let catalog: FieldCatalog
    private let now: () -> Date

    init(draftId: UUID, repository: any TaskRepository, engine: TaskEngine, catalog: FieldCatalog = .mvp,
         now: @escaping () -> Date = { .now }) {
        self.engine = engine
        self.catalog = catalog
        self.now = now
        draft = repository.draft(draftId)
        stepId = draft?.currentStep?.id            // reopen at the exact step (D-244, spec §6.10 AC2)
    }

    // MARK: - Rendering

    var step: TaskStep? { draft?.steps.first { $0.id == stepId } }

    /// `step.<kind>.<operation>` (UI_SCREENS §10.1).
    var titleKey: String? { step.map { "step.\($0.kind.rawValue).\($0.operation.rawValue)" } }

    /// 1-based position and count for `StepIndicator` (shown only when > 1 step).
    var stepPosition: (current: Int, total: Int)? {
        guard let draft, let step, draft.steps.count > 1 else { return nil }
        let ordered = draft.steps.sorted { $0.order < $1.order }
        return ((ordered.firstIndex { $0.id == step.id } ?? 0) + 1, ordered.count)
    }

    /// Catalog order; rows only required under a condition that does not hold now are hidden
    /// (e.g. `contactId` / `phoneNumber` when `channel ≠ sms`, `customLabel` unless `label = custom`).
    var visibleFields: [Field] {
        guard let step, let rule = catalog.rule(step.kind, step.operation) else { return [] }
        let conditionalOnly = Set(rule.conditional.flatMap(\.fields)).subtracting(rule.fields)
        let required = Validator.requiredFieldIds(step, catalog: catalog)
        return catalog.fields(step.kind, step.operation).compactMap { spec in
            if conditionalOnly.contains(spec.id) && !required.contains(spec.id) { return nil }
            // TODO(spec): human rows for 🔒 `contactId` (name + photo + masked number) and `calendarId` (calendar
            // name) need the device services (1C); hidden until then.
            if spec.type == .contactRef || spec.id == "calendarId" { return nil }
            return step.field(spec.id) ?? Field(id: spec.id, type: spec.type, deviceOnly: spec.deviceOnly)
        }
    }

    func displayValue(_ field: Field) -> String? {
        FieldFormatter.display(field, timeZoneId: draft?.timeZoneId ?? TimeZone.current.identifier)
    }

    /// The bottom bar (Xác nhận / Sửa / Hủy) is shown before execution; afterwards the result card (1A.11b).
    var showsActionBar: Bool {
        guard let state = step?.state else { return false }
        return state == .draft || state == .needsInfo || state == .awaitingApproval
    }

    var isDelete: Bool { step?.operation == .delete }

    var blocker: ConfirmBlocker? {
        guard let draft, let stepId else { return .notConfirmable }
        return engine.confirmBlocker(stepId: stepId, in: draft)
    }

    var disabledReasonKey: String? {
        switch blocker {
        case .missing: "review.disabled.missing"
        case .ambiguity: "review.disabled.ambiguity"
        case .previousStep: "review.disabled.previousStep"
        case .notConfirmable, nil: nil
        }
    }

    /// `approval.mismatch` (§8) or "Bạn vừa sửa thông tin, hãy xác nhận lại." after an edit following approval.
    var banner: UserMessage? {
        guard let step else { return nil }
        if step.errorCode == "approval.mismatch" { return UserMessage(key: "error.approval.mismatch") }
        if step.state == .awaitingApproval, step.history.last?.event == .userEdited,
           step.history.contains(where: { $0.event == .userConfirmed }) {
            return UserMessage(key: "review.editedAfterApproval")
        }
        return nil
    }

    var originalInput: String? {
        guard let text = draft?.originalInput, !text.isEmpty else { return nil }
        return UserMessage(key: "review.originalInput", args: [text]).text
    }

    // MARK: - Result card (UI_SCREENS S04 result strings + "Buttons per state", D-250)

    enum ResultAction: Sendable, Hashable {
        case nextStep(UUID), done, markDone, later, retry, cancel
    }

    struct ResultButton: Sendable, Hashable {
        let title: String                 // already localized
        let action: ResultAction
    }

    /// Texts are resolved from `Localizable.xcstrings` (or the executor's Vietnamese `handoffNote`).
    struct ResultCard: Sendable, Hashable {
        let state: TaskState
        let message: String
        /// Second line: error text (`error.<code>`) for `failed`, the step's own result when more steps follow.
        let detail: String?
        let primary: ResultButton?
        let secondary: ResultButton?
    }

    /// Replaces the bottom bar once the step has left draft / needsInfo / awaitingApproval.
    var resultCard: ResultCard? {
        guard let step, !showsActionBar else { return nil }
        let next = nextStep
        let advance = next.map {
            ResultButton(title: UserMessage(key: "result.nextStep",
                                            args: [UserMessage(key: "step.\($0.kind.rawValue).\($0.operation.rawValue)").text]).text,
                         action: .nextStep($0.id))
        } ?? ResultButton(title: UserMessage(key: "common.done").text, action: .done)
        let markDone = ResultButton(title: UserMessage(key: "result.markDone").text, action: .markDone)
        let later = ResultButton(title: UserMessage(key: "common.later").text, action: .later)

        switch step.state {
        case .processing:
            return ResultCard(state: .processing, message: UserMessage(key: "result.processing").text,
                              detail: nil, primary: nil, secondary: nil)
        case .succeeded:
            // TODO(spec): "Mở trong Lịch" / "Mở trong Lời nhắc" (secondary) need the calendar / reminders services (1C).
            let message = next == nil && draft?.isClosed == true ? UserMessage(key: "result.allDone").text : successMessage(step)
            return ResultCard(state: .succeeded, message: message, detail: next == nil ? nil : successMessage(step),
                              primary: advance, secondary: nil)
        case .handedOff, .prepared:
            return ResultCard(state: step.state, message: handOffMessage(step), detail: nil,
                              primary: markDone, secondary: later)
        case .unknown:
            let canRetry = step.kind == .calendarEvent || step.kind == .reminder          // D-243, D-250
            return ResultCard(state: .unknown, message: UserMessage(key: "result.unknown").text, detail: nil,
                              primary: markDone,
                              secondary: canRetry ? ResultButton(title: UserMessage(key: "common.retry").text, action: .retry) : later)
        case .failed:
            // TODO(spec): `permission.<c>.denied` → Primary `perm.<c>.fallback` + "Tôi đã làm xong" comes with S18 (1C.1).
            return ResultCard(state: .failed, message: UserMessage(key: "result.failed").text, detail: errorMessage(step),
                              primary: ResultButton(title: UserMessage(key: "common.retry").text, action: .retry),
                              secondary: ResultButton(title: UserMessage(key: "common.cancel").text, action: .cancel))
        case .userMarkedDone, .cancelled:
            return ResultCard(state: step.state, message: UserMessage(key: step.state.labelKey).text, detail: nil,
                              primary: advance, secondary: nil)
        case .draft, .needsInfo, .awaitingApproval:
            return nil
        }
    }

    /// The next step by `order` that still needs the user (not closed).
    var nextStep: TaskStep? {
        guard let draft, let step else { return nil }
        return draft.steps.filter { $0.order > step.order && !$0.state.isClosed }.min { $0.order < $1.order }
    }

    private func successMessage(_ step: TaskStep) -> String {
        successKey(step).text
    }

    private func successKey(_ step: TaskStep) -> UserMessage {
        switch (step.kind, step.operation) {
        case (.calendarEvent, .create): UserMessage(key: "result.calendarEvent.created")
        case (.calendarEvent, .update): UserMessage(key: "result.calendarEvent.updated")
        case (.calendarEvent, .delete): UserMessage(key: "result.calendarEvent.deleted")
        case (.reminder, .create): UserMessage(key: "result.reminder.created")
        case (.reminder, .complete): UserMessage(key: "result.reminder.completed")
        case (.reminder, .snooze):
            // TODO(spec): the snoozed-to time comes from the executor (1C.5); the step's `dueDate` is shown until then.
            UserMessage(key: "result.reminder.snoozed", args: [step.field("dueDate").flatMap(displayValue) ?? ""])
        case (.sms, _): UserMessage(key: "result.sms.sent")
        case (.place, .create):
            UserMessage(key: "result.place.saved",
                        args: [step.field("customLabel")?.value
                               ?? step.field("label").flatMap(displayValue) ?? ""])
        case (.ocr, _): UserMessage(key: "result.ocr.confirmed")
        default:
            // TODO(spec): no result text for reminder update / delete; the state label "Đã xong" is shown.
            UserMessage(key: TaskState.succeeded.labelKey)
        }
    }

    private func handOffMessage(_ step: TaskStep) -> String {
        switch (step.kind, step.operation) {
        case (.call, _): return UserMessage(key: "result.call.handedOff").text
        case (.place, .open):
            let app = step.field("mapsApp").flatMap(displayValue) ?? ""
            return UserMessage(key: "result.directions.handedOff", args: [app]).text
        default:
            // TODO(spec): no result text for other hand-offs (copy path, D-162); the executor's `handoffNote` or
            // the state label is shown.
            if let note = step.handoffNote { return note }
            return UserMessage(key: step.state.labelKey, args: [""]).text
        }
    }

    /// `error.<code>` (D-249); unknown code → `error.generic` (UI_SCREENS §8).
    private func errorMessage(_ step: TaskStep) -> String? {
        guard let code = step.errorCode else { return nil }
        let key = "error.\(code)"
        let text = UserMessage(key: key).text
        return text == key ? UserMessage(key: "error.generic").text : text
    }

    // MARK: - Intents

    /// "Sửa": the first field needing review, else the first editable field (P-37).
    func startEdit() {
        let fields = visibleFields.filter { Self.isEditableInS05($0.type) }
        editingFieldId = (fields.first(where: \.needsReview) ?? fields.first)?.id
    }

    /// Row tap → S05, except types set by pickers (S06 / S13 in 1C).
    func tapRow(_ field: Field) {
        // TODO(spec): `coordinate` / `placeRef` rows open S13 (1C.13), contact rows open S06 (1C.9).
        if Self.isEditableInS05(field.type) { editingFieldId = field.id }
    }

    static func isEditableInS05(_ type: FieldType) -> Bool {
        type != .contactRef && type != .placeRef && type != .coordinate
    }

    /// S05 for `editingFieldId`; "Lưu" → `TaskEngine.edit` (D-101, D-104).
    var editor: FieldEditorViewModel? {
        guard let id = editingFieldId, let step, let draft,
              let field = visibleFields.first(where: { $0.id == id }) else { return nil }
        return FieldEditorViewModel(field: field, step: step, timeZoneId: draft.timeZoneId, now: now) { [weak self] value in
            self?.edit(fieldId: id, value: value)
        }
    }

    func edit(fieldId: String, value: String?) {
        guard let draft, let stepId else { return }
        engine.edit(fieldId: fieldId, value: value, stepId: stepId, in: draft)
    }

    /// "Xác nhận". Step 0 (permission explainer, D-185) comes with `PermissionManager` (1C.1).
    func confirm() async {
        guard let draft, let stepId else { return }
        _ = await engine.confirm(stepId: stepId, in: draft)
        // TODO(spec): `.needsUI` (SMS composer, ARCHITECTURE §5.3) is presented from 1C.11.
    }

    /// Result card buttons. `done` / `later` are navigation; the View handles them (`didClose` / pop to Home).
    func perform(_ action: ResultAction) {
        guard let draft, let stepId else { return }
        switch action {
        case .nextStep(let id): self.stepId = id
        case .markDone: engine.markDone(stepId: stepId, in: draft)
        case .retry: engine.retry(stepId: stepId, in: draft)
        case .cancel: engine.cancel(stepId: stepId, in: draft)
        case .later: didClose = true
        case .done: didFinish = true
        }
    }

    /// "Hủy": cancels the step (draft kept, D-104) and leaves the screen.
    func cancel() {
        guard let draft, let stepId else { return }
        engine.cancel(stepId: stepId, in: draft)
        didClose = true
    }
}
