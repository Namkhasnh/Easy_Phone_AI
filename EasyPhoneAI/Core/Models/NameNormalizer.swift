import Foundation

/// DATA_MODEL §7.2 `normalize(s)`: diacritic-, case- and width-insensitive folding (locale vi), `đ/Đ → d`,
/// whitespace collapsed, trimmed. `matchKey` also strips leading kinship words (matching only, §7.2).
enum NameNormalizer {
    private static let vi = Locale(identifier: "vi")

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: vi)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// §7.2 kinship words, normalized: anh, chị, em, cô, chú, bác, ông, bà, cháu, con.
    static let kinship: Set<String> = ["anh", "chi", "em", "co", "chu", "bac", "ong", "ba", "chau", "con"]

    /// Normalized text without leading kinship words ("anh Minh" → "minh", "bác Ba" → "ba"); used for matching only,
    /// `recipientName` keeps the original. A text made only of kinship words is kept ("anh" → "anh").
    static func matchKey(_ s: String) -> String {
        var words = normalize(s).split(separator: " ").map(String.init)
        while words.count > 1, let first = words.first, kinship.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }
}
