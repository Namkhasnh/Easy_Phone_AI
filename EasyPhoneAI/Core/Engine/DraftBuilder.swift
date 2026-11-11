import Foundation
import os

/// ARCHITECTURE §5, DATA_MODEL §6.2 "App mapping": `ParsedDraft` (wire) → `TaskStep`s (device). Pure: it never writes
/// `state` beyond the initial `draft` — `TaskEngine.applyParsed` / `mergeAnswer` store the steps and re-validate,
/// which emits `missingRequiredField` / `allRequiredFilled` (D-123).
/// Device resolution (contacts, saved places, calendar search) is `DeviceResolver` (1C), not done here.
enum DraftBuilder {
    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "draftBuilder")

    /// Defaults the app fills when the LLM gave no value (DATA_MODEL §4 "Notes").
    struct Defaults: Sendable, Hashable {
        /// `place.mapsApp` — from `AppSettings.preferredMapsApp` (DATA_MODEL §5).
        var mapsApp: String = "appleMaps"
        /// `ambiguity.date` = "Bạn muốn chọn ngày nào?" (UI_SCREENS §10). Injected so the builder stays pure.
        var dateQuestion: String = String(localized: "ambiguity.date")
    }

    // MARK: - Build from a device event (S11 "Sửa" / "Xóa")

    /// An update / delete step for an existing EventKit event (UI_SCREENS S11): every catalog field filled from the
    /// event with `source = .device("calendar")`, `targetRef` = its identifier (🔒, D-056). Pure; `state = draft`.
    static func step(from event: EventSummary, operation: TaskOperation, timeZoneId: String,
                     catalog: FieldCatalog = .mvp) -> TaskStep {
        let tz = TimeZone(identifier: timeZoneId) ?? .current
        func iso(_ date: Date) -> String {
            let f = ISO8601DateFormatter()
            f.timeZone = tz
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: date)
        }
        let values: [String: String?] = [
            "title": event.title, "startDate": iso(event.start), "endDate": iso(event.end),
            "allDay": event.isAllDay ? "true" : "false", "location": event.location, "notes": event.notes,
            "alertMinutesBefore": event.alertMinutesBefore.map(String.init), "calendarId": event.calendarId,
        ]
        let fields = catalog.fields(.calendarEvent, operation).map { spec in
            Field(id: spec.id, type: spec.type, value: values[spec.id] ?? nil, source: .device(origin: "calendar"),
                  deviceOnly: spec.deviceOnly)
        }
        return TaskStep(order: 0, kind: .calendarEvent, operation: operation, fields: fields, targetRef: event.id)
    }

    // MARK: - Build (first answer)

    /// New steps for `parsed`. `unsupported` → no steps (spec §11). A step whose `kind` / `operation` is unknown or not
    /// in the catalog (invalid pair, Phase 2/3 kind, D-150) is dropped; so are unknown, 🔒 (`deviceOnly`, D-056) and
    /// app-built field ids — the backend already removes them (AI_PROMPTS §9), this is the device-side guard.
    static func steps(from parsed: ParsedDraft, now: Date, defaults: Defaults = .init(),
                      catalog: FieldCatalog = .mvp) -> [TaskStep] {
        guard parsed.unsupported == nil else { return [] }
        var result: [TaskStep] = []
        for parsedStep in parsed.steps {
            guard let step = step(from: parsedStep, order: result.count, now: now,
                                  defaults: defaults, catalog: catalog) else { continue }
            result.append(step)
        }
        return result
    }

    /// One step, fields in catalog order (DATA_MODEL §3.1), `state = draft`. Nil when the pair is not buildable.
    static func step(from parsed: ParsedStep, order: Int, now: Date, defaults: Defaults = .init(),
                     catalog: FieldCatalog = .mvp) -> TaskStep? {
        guard let kind = TaskKind(rawValue: parsed.kind),
              let operation = TaskOperation(rawValue: parsed.operation),
              catalog.rule(kind, operation) != nil else {
            logger.warning("dropped step \(parsed.kind, privacy: .public).\(parsed.operation, privacy: .public)")
            return nil
        }
        let specs = catalog.fields(kind, operation)
        let fields = specs.map { spec in
            field(spec, kind: kind, operation: operation, parsed: parsed, defaults: defaults)
        }
        let step = TaskStep(order: order, kind: kind, operation: operation, state: .draft,
                            fields: fields, stateChangedAt: now)
        return Validator.applyRequired(step, catalog: catalog)
    }

    private static func field(_ spec: FieldSpec, kind: TaskKind, operation: TaskOperation, parsed: ParsedStep,
                              defaults: Defaults) -> Field {
        var field = Field(id: spec.id, type: spec.type, source: .ai, deviceOnly: spec.deviceOnly)
        // 🔒 / app-built ids never come from the LLM (D-056, D-248).
        if !spec.deviceOnly, !spec.appBuilt, let p = parsed.fields.first(where: { $0.id == spec.id }) {
            field.value = cleaned(p.value)
            field.confidence = field.value == nil ? nil : p.confidence
        }
        if field.value == nil, let value = defaultValue(spec, kind: kind, operation: operation, defaults: defaults) {
            field.value = value                         // catalog default: `.ai`, no confidence → no needsReview
        }
        field.ambiguity = dateAmbiguity(for: spec, in: parsed, question: defaults.dateQuestion)
        return field
    }

    /// DATA_MODEL §4 defaults. `endDate` ("start + 60 min") is **not** filled: it would go stale when the user edits
    /// `startDate` and then fail `endBeforeStart`.
    // TODO(spec): DATA_MODEL §4 `endDate` default start + 60 min — applied by CalendarExecutor (1C) when nil.
    static func defaultValue(_ spec: FieldSpec, kind: TaskKind, operation: TaskOperation,
                             defaults: Defaults = .init()) -> String? {
        switch (kind, spec.id) {
        case (.calendarEvent, "allDay"): return "false"
        case (.calendarEvent, "alertMinutesBefore"): return "60"
        case (.sms, "channel"): return "sms"                       // built in, default (DATA_MODEL §4)
        case (.place, "mapsApp"): return defaults.mapsApp
        case (.reminder, "completed"): return "true"               // D-248: `true` = mark done; undo is app-built
        default: return nil
        }
    }

    /// `dateCandidates` for this field → `Ambiguity(kind: .date)` (DATA_MODEL §2.1). Never auto-picked, even with one
    /// candidate (D-106); picking one is local (D-251). Invalid values are already dropped by the backend (§9).
    /// Only `dateTime` fields take candidates (their `value` is a dateTime, AI_PROMPTS §9).
    private static func dateAmbiguity(for spec: FieldSpec, in parsed: ParsedStep, question: String) -> Ambiguity? {
        guard spec.type == .dateTime else { return nil }
        let candidates = parsed.dateCandidates
            .filter { $0.fieldId == spec.id && Validator.parseDateTime($0.value) != nil }
            .map { Candidate(id: $0.value, title: $0.label, subtitle: nil, imageRef: nil) }
        guard !candidates.isEmpty else { return nil }
        return Ambiguity(kind: .date, question: question, candidates: candidates)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Back to the wire (`context.currentDraft`, DATA_MODEL §6.2)

    /// The draft as a `ParsedDraft` for a follow-up `/v1/parse`: steps in `order`, **no 🔒 field** (`deviceOnly`,
    /// D-056) and no app-built field, no `targetRef` / evidence / state (the DTO has no such key), date ambiguities as
    /// `dateCandidates`. `sourceQuote` is not stored on device → `null`.
    static func wireDraft(_ draft: TaskDraft, catalog: FieldCatalog = .mvp) -> ParsedDraft {
        let steps = draft.steps.sorted { $0.order < $1.order }.map { step in
            let visible = step.fields.filter { field in
                let spec = catalog.fields(step.kind, step.operation).first { $0.id == field.id }
                return !field.deviceOnly && spec?.deviceOnly != true && spec?.appBuilt != true
            }
            return ParsedStep(
                kind: step.kind.rawValue, operation: step.operation.rawValue,
                fields: visible.map { ParsedField(id: $0.id, value: $0.value,
                                                  confidence: $0.value == nil ? nil : $0.confidence, sourceQuote: nil) },
                dateCandidates: visible.flatMap { field -> [ParsedDateCandidate] in
                    guard let a = field.ambiguity, a.kind == .date else { return [] }
                    return a.candidates.map { ParsedDateCandidate(fieldId: field.id, value: $0.id, label: $0.title) }
                })
        }
        return ParsedDraft(schemaVersion: 1, requestId: draft.serverRequestId, steps: steps,
                           followUpQuestion: draft.followUpQuestion, unsupported: nil)
    }

    // MARK: - Merge (follow-up answer, API_CONTRACT §7.1 Example B)

    /// States whose fields a follow-up answer may change. A step that already ran (or is running) is never touched.
    static let mergeableStates: Set<TaskState> = [.draft, .needsInfo, .awaitingApproval]

    /// Merges the answer `parsed` into `existing`: only fields that changed are updated; fields the user set
    /// (`source = .user`) and device-resolved / linked / OCR fields are kept. Steps are matched by position
    /// with the same kind + operation.
    // TODO(spec): API_CONTRACT §7.1 does not say how steps are matched, what a `null` in the answer means for a value
    // the draft already has, or what to do with extra / missing steps. Chosen: match by position + same kind and
    // operation; `null` keeps the old value (the LLM forgot it, the user did not clear it); extra answer steps and
    // unmatched existing steps are left as they are.
    static func merge(_ parsed: ParsedDraft, into existing: [TaskStep], defaults: Defaults = .init(),
                      catalog: FieldCatalog = .mvp) -> [TaskStep] {
        guard parsed.unsupported == nil else { return existing }
        var result = existing
        for (index, current) in existing.enumerated() where mergeableStates.contains(current.state) {
            guard index < parsed.steps.count else { break }
            let answer = parsed.steps[index]
            guard answer.kind == current.kind.rawValue, answer.operation == current.operation.rawValue else {
                logger.warning("merge: step \(index, privacy: .public) kind/operation differs, kept")
                continue
            }
            var step = current
            for f in step.fields.indices where step.fields[f].source == .ai {
                let id = step.fields[f].id
                guard let spec = catalog.fields(step.kind, step.operation).first(where: { $0.id == id }),
                      !spec.deviceOnly, !spec.appBuilt else { continue }
                if let p = answer.fields.first(where: { $0.id == id }), let value = cleaned(p.value),
                   value != step.fields[f].value {
                    step.fields[f].value = value
                    step.fields[f].confidence = p.confidence
                    step.fields[f].ambiguity = nil
                }
                // New candidates replace old ones; none in the answer → an old date question stays only while
                // the field is still empty.
                if let ambiguity = dateAmbiguity(for: spec, in: answer, question: defaults.dateQuestion) {
                    step.fields[f].ambiguity = ambiguity
                } else if step.fields[f].value != nil {
                    step.fields[f].ambiguity = nil
                }
            }
            result[index] = Validator.applyRequired(step, catalog: catalog)
        }
        return result
    }
}
