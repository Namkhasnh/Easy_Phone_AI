import Foundation
import Observation

/// S05 Field editor (UI_SCREENS S05). Holds the value being edited; "Lưu" hands the encoded value
/// (DATA_MODEL §1.6) to `onSave`, which forwards to `TaskEngine.edit` (autosave, D-104).
@Observable @MainActor final class FieldEditorViewModel {
    let field: Field
    let kind: TaskKind
    let timeZone: TimeZone

    /// Text-like value (text, longText, address, phone, enumChoice, durationMinutes, bool as "true"/"false").
    var text: String
    /// Date-like value (dateTime, date), in `timeZone`.
    var date: Date

    private let step: TaskStep
    private let now: () -> Date
    private let onSave: (String?) -> Void

    init(field: Field, step: TaskStep, timeZoneId: String, now: @escaping () -> Date = { .now },
         onSave: @escaping (String?) -> Void) {
        self.field = field
        self.kind = step.kind
        self.step = step
        self.timeZone = TimeZone(identifier: timeZoneId) ?? .current
        self.now = now
        self.onSave = onSave
        text = field.value ?? ""
        switch field.type {
        case .dateTime:
            date = field.value.flatMap(Validator.parseDateTime) ?? Self.nextFullHour(after: now(), in: TimeZone(identifier: timeZoneId) ?? .current)
        case .date:
            date = field.value.flatMap { Self.parseDay($0, in: TimeZone(identifier: timeZoneId) ?? .current) } ?? now()
        default:
            date = now()
        }
    }

    var titleKey: String { field.labelKey(kind: kind) }

    /// Choices for `enumChoice` / `durationMinutes` (catalog options; alert list P-35 keeps a non-listed AI value).
    var options: [String] {
        switch field.type {
        case .enumChoice:
            return FieldCatalog.mvp.fields(kind, step.operation).first { $0.id == field.id }?.options ?? []
        case .durationMinutes where field.id == "alertMinutesBefore":
            var list = ["0", "15", "60", "1440"]
            if let v = field.value, !list.contains(v) { list.append(v) }
            return list
        default:
            return []
        }
    }

    func optionLabel(_ value: String) -> String {
        FieldFormatter.option(fieldId: field.id, value: value, args: optionArgs(value)) ?? value
    }

    /// The encoded value "Lưu" would store; nil = empty.
    var encodedValue: String? {
        switch field.type {
        case .dateTime: return Self.iso(date, in: timeZone)
        case .date: return Self.day(date, in: timeZone)
        case .text, .address:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .phone:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (Validator.normalizePhone(trimmed) ?? trimmed)
        default:
            return text.isEmpty ? nil : text
        }
    }

    /// Inline error (`editor.invalid.*`), shown in `danger` with an icon; "Lưu" is disabled while set.
    var invalidMessage: UserMessage? {
        switch Validator.check(fieldId: field.id, value: encodedValue, in: step, now: now()) {
        case .endBeforeStart: return UserMessage(key: "editor.invalid.endBeforeStart")
        case .inPast: return UserMessage(key: "editor.invalid.past")
        case .invalidEncoding:
            switch field.type {
            case .phone: return UserMessage(key: "editor.invalid.phone")
            case .text: return UserMessage(key: "editor.invalid.tooLong", args: ["2000"])
            case .longText: return UserMessage(key: "editor.invalid.tooLong", args: ["10000"])
            // TODO(spec): no editor message for other invalid encodings (pickers cannot produce them).
            default: return UserMessage(key: "error.generic")
            }
        default: return nil
        }
    }

    var canSave: Bool { invalidMessage == nil }

    // MARK: - Intents

    /// Chips "Hôm nay" / "Ngày mai": change the day, keep the time.
    func setDay(offset: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let time = cal.dateComponents([.hour, .minute], from: date)
        let base = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now())) ?? now()
        date = cal.date(bySettingHour: time.hour ?? 8, minute: time.minute ?? 0, second: 0, of: base) ?? base
    }

    func clear() { text = "" }

    func save() {
        guard canSave else { return }
        onSave(encodedValue)
    }

    // MARK: - Encoding helpers

    private func optionArgs(_ value: String) -> [String] {
        // TODO(spec): the snooze hour comes from `AppSettings.snoozeMorningHour` (S15, 1C.17); default 8 until then.
        field.id == "snoozeOption" && value == "tomorrowMorning" ? ["8"] : []
    }

    static func iso(_ date: Date, in tz: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = tz
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func day(_ date: Date, in tz: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func parseDay(_ value: String, in tz: TimeZone) -> Date? {
        guard let m = value.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: Int(m.1), month: Int(m.2), day: Int(m.3), hour: 12))
    }

    /// Empty dateTime starts at the next full hour.
    // TODO(spec): the default time of an empty date-time editor is not specified.
    private static func nextFullHour(after date: Date, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.dateInterval(of: .hour, for: date)?.start ?? date
        return cal.date(byAdding: .hour, value: 1, to: start) ?? date
    }
}
