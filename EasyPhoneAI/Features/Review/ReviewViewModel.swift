import Foundation
import Observation

/// S04 Review (UI_SCREENS S04, spec §5.3, ARCHITECTURE §2.1). Forwards intents to `TaskEngine`; no business rules.
/// Holds the `@Model` draft itself (observable) instead of a value snapshot so edits made by the engine show at once.
@Observable @MainActor final class ReviewViewModel {
    private(set) var draft: TaskDraft?
    private(set) var stepId: UUID?
    /// Field whose editor (S05, 1A.12) should open.
    var editingFieldId: String?
    /// Set after "Hủy": the View pops back.
    private(set) var didClose = false

    private let engine: TaskEngine
    private let catalog: FieldCatalog

    init(draftId: UUID, repository: any TaskRepository, engine: TaskEngine, catalog: FieldCatalog = .mvp) {
        self.engine = engine
        self.catalog = catalog
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

    // MARK: - Intents

    /// "Sửa": the first field needing review, else the first field (P-37).
    func startEdit() {
        let fields = visibleFields
        editingFieldId = (fields.first(where: \.needsReview) ?? fields.first)?.id
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

    /// "Hủy": cancels the step (draft kept, D-104) and leaves the screen.
    func cancel() {
        guard let draft, let stepId else { return }
        engine.cancel(stepId: stepId, in: draft)
        didClose = true
    }
}
