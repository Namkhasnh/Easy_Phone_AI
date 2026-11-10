import Foundation

/// One reason a step cannot leave `needsInfo` / cannot be confirmed (DATA_MODEL §7.1).
struct ValidationIssue: Sendable, Hashable {
    enum Reason: String, Sendable, Hashable {
        case missingTargetRef          // §4.1 lists `targetRef` (update/delete/complete/snooze)
        case missing                   // required field absent or empty
        case invalidEncoding           // value does not match its `FieldType` encoding (§1.6)
        case ambiguous                 // `ambiguity != nil` (D-106)
        case endBeforeStart            // `endDate <= startDate`
        case inPast                    // `startDate` / `dueDate` more than 5 min in the past
        case unknownOption             // enum value / service id not allowed (D-247)
        case unsupportedOperation      // `(kind, operation)` not in the catalog (§1.2, D-150)
    }

    /// Catalog field id; nil for `missingTargetRef` / `unsupportedOperation`.
    var fieldId: String?
    var reason: Reason
}

/// DATA_MODEL §7.1 — pure. Empty result → `allRequiredFilled`, else `missingRequiredField` (ARCHITECTURE §5).
/// Issues are ordered: `targetRef` first, then fields in catalog order; the follow-up targets the first one.
enum Validator {
    /// Rule 3: dates up to this far in the past are still accepted.
    static let pastTolerance: TimeInterval = 5 * 60

    static func validate(
        _ step: TaskStep,
        now: Date,
        serviceIds: Set<String> = [],          // SupportedServices.json ids (DATA_MODEL §10, 1C.12)
        catalog: FieldCatalog = .mvp
    ) -> [ValidationIssue] {
        guard let rule = catalog.rule(step.kind, step.operation) else {
            return [ValidationIssue(fieldId: nil, reason: .unsupportedOperation)]
        }
        let specs = catalog.fields(step.kind, step.operation)
        let required = requiredFieldIds(step, catalog: catalog)
        var issues: [ValidationIssue] = []

        if rule.requiresTargetRef, isEmpty(step.targetRef) {
            issues.append(ValidationIssue(fieldId: nil, reason: .missingTargetRef))
        }

        for spec in specs {                                   // catalog order (§4); §4.1 ids are all catalog ids
            let id = spec.id
            if let issue = fieldIssue(id: id, spec: spec, field: step.field(id), isRequired: required.contains(id),
                                      step: step, now: now, serviceIds: serviceIds) {
                issues.append(issue)
            }
        }
        return issues
    }

    /// §4.1 required field ids for the step's `(kind, operation)` and current `channel` / `label` / `recipientName`.
    static func requiredFieldIds(_ step: TaskStep, catalog: FieldCatalog = .mvp) -> Set<String> {
        guard let rule = catalog.rule(step.kind, step.operation) else { return [] }
        var ids = Set(rule.fields)
        for extra in rule.conditional where extra.when.allSatisfy({ holds($0, in: step) }) {
            ids.formUnion(extra.fields)
        }
        return ids
    }

    /// Recomputes `Field.required` (ARCHITECTURE §5: whenever `channel` / `label` change).
    static func applyRequired(_ step: TaskStep, catalog: FieldCatalog = .mvp) -> TaskStep {
        let ids = requiredFieldIds(step, catalog: catalog)
        var copy = step
        for i in copy.fields.indices { copy.fields[i].required = ids.contains(copy.fields[i].id) }
        return copy
    }

    // MARK: - Rules

    private static func fieldIssue(
        id: String, spec: FieldSpec, field: Field?, isRequired: Bool,
        step: TaskStep, now: Date, serviceIds: Set<String>
    ) -> ValidationIssue? {
        func issue(_ r: ValidationIssue.Reason) -> ValidationIssue { ValidationIssue(fieldId: id, reason: r) }

        // Rule 2: any ambiguity blocks, required or not.
        if field?.ambiguity != nil { return issue(.ambiguous) }

        guard let value = field?.value, !isEmpty(value) else {
            return isRequired ? issue(.missing) : nil
        }
        // Rule 1: encoding is checked for required fields (§7.1 wording).
        // TODO(spec): DATA_MODEL §7.1 checks encoding of required fields only; optional values are not checked.
        let type = spec.type
        if isRequired {
            if type == .enumChoice {
                if !isAllowedOption(id: id, value: value, spec: spec, step: step, serviceIds: serviceIds) {
                    return issue(.unknownOption)
                }
            } else if !isEncoded(value, as: type) {
                return issue(.invalidEncoding)
            }
        } else if id == "channel" || id == "service",
                  !isAllowedOption(id: id, value: value, spec: spec, step: step, serviceIds: serviceIds) {
            return issue(.unknownOption)                                   // Rule 4 applies to any channel value
        }

        // Rule 3: cross-field, only on fields the operation requires (delete hints are not checked).
        guard isRequired || id == "endDate" else { return nil }
        switch id {
        case "endDate":
            if let end = parseDateTime(value),
               let startValue = step.field("startDate")?.value, let start = parseDateTime(startValue),
               end <= start {
                return issue(.endBeforeStart)
            }
        case "startDate", "dueDate":
            if let date = parseDateTime(value), date < now.addingTimeInterval(-pastTolerance) {
                return issue(.inPast)
            }
        default: break
        }
        return nil
    }

    /// Rule 4 (D-247): `channel = "sms"` is always valid; other ids must be in SupportedServices.json.
    private static func isAllowedOption(
        id: String, value: String, spec: FieldSpec, step: TaskStep, serviceIds: Set<String>
    ) -> Bool {
        if id == "channel" || id == "service" {
            return (id == "channel" && value == "sms") || serviceIds.contains(value)
        }
        guard let options = spec.options else { return false }
        return options.contains(value)
    }

    private static func holds(_ condition: RequirementCondition, in step: TaskStep) -> Bool {
        switch condition {
        case let .equals(field, value):
            return step.field(field)?.value == value
        case let .notPhoneNumber(field):
            return !isPhoneNumber(step.field(field)?.value)
        }
    }

    // MARK: - Encodings (DATA_MODEL §1.6)

    static func isEncoded(_ value: String, as type: FieldType) -> Bool {
        switch type {
        case .text:
            return value == value.trimmingCharacters(in: .whitespacesAndNewlines) && value.count <= 2000
        case .longText:
            return value.count <= 10_000
        case .dateTime:
            return parseDateTime(value) != nil
        case .date:
            return parseDate(value) != nil
        case .durationMinutes:
            return value.allSatisfy(\.isASCIIDigit) && Int(value) != nil
        case .bool:
            return value == "true" || value == "false"
        case .phone:
            return value.wholeMatch(of: /\+[1-9][0-9]{6,14}/) != nil     // E.164 after device normalization
        case .contactRef, .placeRef, .enumChoice:
            return true                                                  // opaque / checked by options
        case .address:
            return !value.contains("\n")
        case .coordinate:
            let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return false }
            return (-90...90).contains(lat) && (-180...180).contains(lng)
        }
    }

    /// ISO 8601 with offset, e.g. `2026-11-09T14:00:00+07:00` (seconds required, fraction optional).
    static func parseDateTime(_ value: String) -> Date? {
        guard value.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})/) != nil
        else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = value.contains(".")
            ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// `YYYY-MM-DD`, a real calendar day.
    static func parseDate(_ value: String) -> Date? {
        guard let m = value.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/),
              let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: y, month: mo, day: d)
        guard comps.isValidDate(in: cal) else { return nil }
        return cal.date(from: comps)
    }

    /// D-253: `recipientName` is a phone number (DATA_MODEL §7.3: strip spaces / dots / dashes, VN local or E.164).
    // TODO(spec): full phone normalization + masking is 1C.8; this check only recognises the §7.3 forms.
    static func isPhoneNumber(_ value: String?) -> Bool {
        guard let value else { return false }
        let stripped = value.filter { !" .-".contains($0) }
        return stripped.wholeMatch(of: /0[0-9]{9}/) != nil
            || stripped.wholeMatch(of: /\+[1-9][0-9]{6,14}/) != nil
    }

    /// DATA_MODEL §7.3: strip spaces / dots / dashes; VN local `0xxxxxxxxx` → `+84xxxxxxxxx`.
    /// Returns nil when the result is not E.164. (Masking + the full test set: 1C.8.)
    static func normalizePhone(_ value: String) -> String? {
        let stripped = value.filter { !" .-".contains($0) }
        let e164 = stripped.wholeMatch(of: /0[0-9]{9}/) != nil ? "+84" + stripped.dropFirst() : stripped
        return isEncoded(e164, as: .phone) ? e164 : nil
    }

    /// S05 inline check of one edited value (UI_SCREENS S05): encoding of any non-empty value (required or not)
    /// plus the §7.1 cross-field rules for that field. Empty → nil (the Review row then shows "Chưa có").
    static func check(fieldId: String, value: String?, in step: TaskStep, now: Date,
                      catalog: FieldCatalog = .mvp) -> ValidationIssue.Reason? {
        guard let value, !isEmpty(value),
              let spec = catalog.fields(step.kind, step.operation).first(where: { $0.id == fieldId }) else { return nil }
        if spec.type != .enumChoice, !isEncoded(value, as: spec.type) { return .invalidEncoding }
        var copy = step
        if let i = copy.fields.firstIndex(where: { $0.id == fieldId }) {
            copy.fields[i].value = value
            copy.fields[i].ambiguity = nil
        } else {
            copy.fields.append(Field(id: fieldId, type: spec.type, value: value))
        }
        let crossField: Set<ValidationIssue.Reason> = [.endBeforeStart, .inPast]
        return validate(copy, now: now, catalog: catalog)
            .first { $0.fieldId == fieldId && crossField.contains($0.reason) }?.reason
    }

    private static func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
