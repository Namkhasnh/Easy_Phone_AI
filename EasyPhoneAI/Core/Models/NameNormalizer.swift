import Foundation

/// DATA_MODEL §7.2 `normalize(s)`: diacritic-, case- and width-insensitive folding (locale vi), `đ/Đ → d`,
/// whitespace collapsed, trimmed. Kinship stripping and contact matching come with 1C.7.
enum NameNormalizer {
    private static let vi = Locale(identifier: "vi")

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: vi)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
