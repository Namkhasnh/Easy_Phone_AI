import Foundation

/// A step-by-step guide shown by "Khoai hướng dẫn" (D-337), from the curated set or from `POST /v1/guide` (D-338).
/// Nothing runs on the phone: the user follows the steps.
struct Guide: Codable, Sendable, Hashable {
    enum Source: Codable, Sendable, Hashable {
        /// `Resources/Guides.json` entry id (checked on the owner's iPhone, D-338).
        case curated(id: String)
        /// AI-written generic guide; the UI adds "Các app có thể khác nhau…" (D-338).
        case ai(requestId: String)
    }

    var title: String
    var steps: [GuideResponse.Step]
    var isMoneyRelated: Bool
    /// AI-inferred situation warnings only; the 3 fixed warnings are app strings (D-339, 4H.4).
    var scamWarnings: [String]
    var source: Source
}

extension GuideResponse {
    /// nil = `unsupported` or no steps → "Chưa hỗ trợ".
    var guide: Guide? {
        guard unsupported == nil, !steps.isEmpty else { return nil }
        return Guide(title: title ?? "", steps: steps, isMoneyRelated: isMoneyRelated, scamWarnings: scamWarnings,
                     source: .ai(requestId: requestId))
    }
}

/// 4H.2 (D-338): the curated guide set `Resources/Guides.json` (bundled, read-only, vi). Matched on the device first:
/// a match costs no AI call and no unit; no match → `POST /v1/guide`.
struct GuideLibrary: Codable, Sendable, Hashable {
    struct Entry: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        /// The owner followed every step on the iPhone (D-338). Unchecked entries are used in Debug builds only.
        let verified: Bool
        let isMoneyRelated: Bool
        /// Any pattern matches when **all** its phrases appear as whole words in the folded question
        /// (`NameNormalizer.normalize`, no diacritics, lowercase).
        let match: [[String]]
        /// A folded phrase here → never this entry. Money entries list scam situations ("gọi điện", "công an", "OTP"…)
        /// so those questions go to the AI, which warns about the situation the user told (D-339).
        let exclude: [String]
        let steps: [GuideResponse.Step]

        var guide: Guide {
            Guide(title: title, steps: steps, isMoneyRelated: isMoneyRelated, scamWarnings: [], source: .curated(id: id))
        }
    }

    let schemaVersion: Int
    /// Bumped on every content change.
    let version: Int
    let guides: [Entry]

    #if DEBUG
    static let usesUnverified = true
    #else
    static let usesUnverified = false
    #endif

    /// The entry for `question`, or nil (→ AI). Score = letters of the best matching pattern; a tie between two
    /// entries → nil, never a guess (D-106 spirit: the AI answers instead).
    func match(_ question: String, includeUnverified: Bool = usesUnverified) -> Entry? {
        let text = " " + Self.fold(question) + " "
        func has(_ phrase: String) -> Bool { text.contains(" \(phrase) ") }
        var best: (entry: Entry, score: Int)?
        var tied = false
        for entry in guides where entry.verified || includeUnverified {
            guard !entry.exclude.contains(where: has) else { continue }
            let score = entry.match.filter { $0.allSatisfy(has) }.map { $0.joined().count }.max() ?? 0
            guard score > 0 else { continue }
            if let b = best, score == b.score { tied = true }
            if score > (best?.score ?? 0) { best = (entry, score); tied = false }
        }
        return tied ? nil : best?.entry
    }

    /// Folded words only: punctuation → spaces ("Wi-Fi" → "wi fi", "zalo?" → "zalo").
    static func fold(_ s: String) -> String {
        let folded = NameNormalizer.normalize(s).lowercased()
        return String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ").joined(separator: " ")
    }

    /// Loaded once from the app bundle; a missing / broken file = no curated guides (everything goes to the AI).
    static let bundled: GuideLibrary = {
        guard let url = Bundle.main.url(forResource: "Guides", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(GuideLibrary.self, from: data) else {
            return GuideLibrary(schemaVersion: 1, version: 0, guides: [])
        }
        return decoded
    }()
}
