import Foundation

/// The ONE follow-up question S03 asks (spec §6.2 AC3, UI_SCREENS S03 mode 4).
struct FollowUpPrompt: Sendable, Hashable {
    let stepId: UUID
    let fieldId: String
    /// Vietnamese, ready to show / read aloud: the backend `followUpQuestion` (D-281) or a catalog text.
    let question: String
    /// `.date` ambiguity candidates → chips; picking one is local (D-251).
    let candidates: [Candidate]
}

/// D-281: the app's `Validator` alone decides **whether** to ask, and about which field (the first issue).
/// The backend `followUpQuestion` is wording only — used when it targets that same field, else
/// `followup.<kind>.<fieldId>`; ignored when there is no issue (DATA_MODEL §7.1, API_CONTRACT §7.1).
enum FollowUpPlanner {
    struct Target: Sendable, Hashable {
        let stepId: UUID
        let fieldId: String
    }

    /// UI_SCREENS §10.4 has a text for these `<kind>.<fieldId>`; any other field uses `followup.generic`.
    static let questionKeys: Set<String> = [
        "calendarEvent.title", "calendarEvent.startDate", "reminder.dueDate", "reminder.title",
        "call.recipientName", "sms.recipientName", "sms.body", "place.query",
    ]

    /// The field to ask about: first `needsInfo` step by `order`, its first issue the user can answer **by voice /
    /// text / chip** in S03.
    // TODO(spec): D-281 says "the first issue". Issues S03 cannot answer — `targetRef` (search picker), 🔒 contact /
    // phone fields, contact / place ambiguities (pickers S06/S13, 1C) — are skipped here and fixed on S04; when
    // nothing askable is left the flow opens S04.
    static func target(in draft: TaskDraft, now: Date, serviceIds: Set<String> = [],
                       catalog: FieldCatalog = .mvp) -> Target? {
        for step in draft.steps.sorted(by: { $0.order < $1.order }) where step.state == .needsInfo {
            for issue in Validator.validate(step, now: now, serviceIds: serviceIds, catalog: catalog) {
                guard let fieldId = issue.fieldId, let field = step.field(fieldId), isAskable(field) else { continue }
                return Target(stepId: step.id, fieldId: fieldId)
            }
        }
        return nil
    }

    /// The field the backend's `followUpQuestion` was about, read from freshly built / merged steps (before any
    /// device resolution): the first step, first required LLM-visible field still empty or date-ambiguous —
    /// AI_PROMPTS §3 "ONE short question about the first missing field".
    // TODO(spec): `ParsedDraft` does not say which field `followUpQuestion` targets (API_CONTRACT §7.1); inferred.
    static func llmTarget(of steps: [TaskStep], catalog: FieldCatalog = .mvp) -> Target? {
        for step in steps.sorted(by: { $0.order < $1.order }) {
            let specs = catalog.fields(step.kind, step.operation)
            for spec in specs where !spec.deviceOnly && !spec.appBuilt {
                guard let field = step.field(spec.id), field.required || field.ambiguity != nil else { continue }
                if field.value == nil || field.ambiguity?.kind == .date { return Target(stepId: step.id, fieldId: spec.id) }
            }
        }
        return nil
    }

    /// D-281 applied to a fresh `/v1/parse` answer: the backend wording survives only when it targets the field the
    /// app will ask about. Result = new `TaskDraft.followUpQuestion`.
    static func wording(_ followUpQuestion: String?, llmTarget: Target?, appTarget: Target?) -> String? {
        guard let q = followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty,
              let appTarget, llmTarget == appTarget else { return nil }
        return q
    }

    /// The prompt for `draft`, or nil = nothing to ask in S03 (→ S04).
    /// `draft.followUpQuestion` is already filtered by `wording` (D-281) and cleared by any user edit.
    static func next(in draft: TaskDraft, now: Date, serviceIds: Set<String> = [],
                     catalog: FieldCatalog = .mvp) -> FollowUpPrompt? {
        guard let t = target(in: draft, now: now, serviceIds: serviceIds, catalog: catalog),
              let step = draft.steps.first(where: { $0.id == t.stepId }),
              let field = step.field(t.fieldId) else { return nil }
        let candidates = field.ambiguity?.kind == .date ? field.ambiguity?.candidates ?? [] : []
        let question = draft.followUpQuestion
            ?? (candidates.isEmpty ? nil : field.ambiguity?.question)
            ?? catalogQuestion(kind: step.kind, field: field)
        return FollowUpPrompt(stepId: step.id, fieldId: field.id, question: question, candidates: candidates)
    }

    /// `followup.<kind>.<fieldId>`, else `followup.generic` with the field label (UI_SCREENS §10.4).
    static func catalogQuestion(kind: TaskKind, field: Field) -> String {
        let name = "\(kind.rawValue).\(field.id)"
        if questionKeys.contains(name) { return UserMessage(key: "followup.\(name)").text }
        let label = String(localized: String.LocalizationValue(field.labelKey(kind: kind)))
        return UserMessage(key: "followup.generic", args: [label]).text
    }

    /// Voice / text / chip can fill it: not 🔒, no contact / place / phone ambiguity (those need on-device pickers).
    private static func isAskable(_ field: Field) -> Bool {
        guard !field.deviceOnly else { return false }
        if let kind = field.ambiguity?.kind { return kind == .date || kind == .other }
        return true
    }
}
