import Foundation

/// Turns a field's encoded `value` (DATA_MODEL §1.6) into the text a person reads on Review / History.
/// Pure; all words come from `Localizable.xcstrings` (D-003). Returns nil when there is nothing to show
/// (the row then says "Chưa có").
enum FieldFormatter {
    static func display(_ field: Field, timeZoneId: String, snoozeMorningHour: Int = 8) -> String? {
        guard let value = field.value, !value.isEmpty else { return nil }
        let tz = TimeZone(identifier: timeZoneId) ?? .current
        switch field.type {
        case .dateTime:
            guard let date = Validator.parseDateTime(value) else { return value }
            return dateTime(date, timeZone: tz)
        case .date:
            guard let date = Validator.parseDate(value) else { return value }
            // `common.dateTimeFormat` date part: "{weekday}, {dd/MM}". Parsed at UTC midnight → format in UTC.
            return "\(weekday(date, tz: TimeZone(identifier: "UTC")!)), \(format(date, "dd/MM", TimeZone(identifier: "UTC")!))"
        case .enumChoice, .durationMinutes:
            let args = field.id == "snoozeOption" && value == "tomorrowMorning" ? ["\(snoozeMorningHour)"] : []
            return option(fieldId: field.id, value: value, args: args) ?? value
        case .bool:
            // TODO(spec): no key for bool values (DOC-25); `common.yes` / `common.no`.
            return UserMessage(key: value == "true" ? "common.yes" : "common.no").text
        case .contactRef, .placeRef:
            // 🔒 opaque identifiers are never shown; their human row comes from the device services (1C).
            return nil
        case .text, .longText, .phone, .address, .coordinate:
            return value
        }
    }

    /// `common.dateTimeFormat` = "{weekday}, {dd/MM} lúc {HH:mm}" (24 h), e.g. "Thứ Hai, 09/11 lúc 14:00".
    static func dateTime(_ date: Date, timeZone: TimeZone) -> String {
        UserMessage(key: "common.dateTimeFormat",
                    args: [weekday(date, tz: timeZone), format(date, "dd/MM", timeZone), format(date, "HH:mm", timeZone)]).text
    }

    /// `option.<fieldId>.<value>` (UI_SCREENS §10.3), nil when the catalog has no such key.
    static func option(fieldId: String, value: String, args: [String] = []) -> String? {
        let key = "option.\(fieldId).\(value)"
        let text = UserMessage(key: key, args: args).text
        return text == key ? nil : text
    }

    private static func weekday(_ date: Date, tz: TimeZone) -> String {
        // vi weekday names ("Thứ Hai" … "Chủ Nhật"), capitalized as in UI_SCREENS §5.
        format(date, "EEEE", tz, locale: Locale(identifier: "vi_VN")).capitalized(with: Locale(identifier: "vi_VN"))
    }

    private static func format(_ date: Date, _ pattern: String, _ tz: TimeZone, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
