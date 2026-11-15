import Foundation

/// DATA_MODEL §7.3 phone normalization + masking (D-253, D-205). Pure.
/// Normalized form = E.164 (`+` and 7–15 digits); Vietnamese local `0xxxxxxxxx` → `+84xxxxxxxxx`.
enum PhoneNumber {
    /// Characters removed before parsing: spaces, dots, dashes (§7.3).
    // TODO(spec): §7.3 lists spaces / dots / dashes only; parentheses and non-breaking spaces (common in iOS Contacts,
    // e.g. "(090) 123 4567") are removed too, and an international "00" prefix is read as "+".
    private static let separators: Set<Character> = [" ", ".", "-", "(", ")", "\u{00A0}"]

    /// E.164, or nil when `raw` is not a usable phone number (too short / long, letters, short codes like "113").
    static func normalize(_ raw: String) -> String? {
        var s = String(raw.filter { !separators.contains($0) })
        if s.hasPrefix("00") { s = "+" + s.dropFirst(2) }
        // TODO(spec): §7.3 pattern `0xxxxxxxxx` = 10-digit mobile; 11-digit landlines ("024 3xxx xxxx") are not
        // converted (PROGRESS DOC-40).
        if s.wholeMatch(of: /0[0-9]{9}/) != nil { s = "+84" + s.dropFirst() }   // VN local, 10 digits
        return s.wholeMatch(of: /\+[1-9][0-9]{6,14}/) != nil ? s : nil
    }

    /// The text is a phone number (D-253: then it goes to `phoneNumber`, no contact lookup).
    static func isPhone(_ raw: String?) -> Bool {
        raw.flatMap(normalize) != nil
    }

    /// Picker / Review form "•••• 567" (§7.3, UI_SCREENS S06): only the last 3 digits are shown.
    static func masked(_ raw: String) -> String {
        let digits = (normalize(raw) ?? raw).filter(\.isNumber)
        return "•••• " + String(digits.suffix(3))
    }

    /// Same number written differently ("0901 234 567" vs "+84901234567").
    static func same(_ a: String, _ b: String) -> Bool {
        guard let x = normalize(a), let y = normalize(b) else { return false }
        return x == y
    }
}
