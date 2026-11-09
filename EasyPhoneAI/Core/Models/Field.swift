import Foundation

/// DATA_MODEL §2. One field of a step; `id` is the catalog id (§4). Labels are not stored (D-220).
struct Field: Codable, Sendable, Identifiable, Hashable {
    let id: String              // catalog id, e.g. "startDate" (§4)
    var type: FieldType
    var value: String?          // encoded per FieldType (§1.6); nil = empty
    var required: Bool          // from §4.1 for the step's (kind, operation) + current values
    var source: FieldSource
    var confidence: Double?     // 0…1, AI/OCR only; < 0.7 → needsReview (D-126)
    var ambiguity: Ambiguity?   // non-nil blocks "Xác nhận" until resolved (D-106)
    var deviceOnly: Bool        // 🔒 never serialized to backend payloads (D-056)

    init(
        id: String,
        type: FieldType,
        value: String? = nil,
        required: Bool = false,
        source: FieldSource = .user,
        confidence: Double? = nil,
        ambiguity: Ambiguity? = nil,
        deviceOnly: Bool = false
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.required = required
        self.source = source
        self.confidence = confidence
        self.ambiguity = ambiguity
        self.deviceOnly = deviceOnly
    }
}

extension Field {
    /// D-126 + DATA_MODEL §2.
    var needsReview: Bool { (confidence ?? 1) < 0.7 || source.isOCR || ambiguity != nil }

    /// `field.<kind>.<id>` in `Localizable.xcstrings`.
    // TODO(spec): DATA_MODEL §2 declares `labelKey` without arguments, but `Field` stores no kind — the step's kind is passed in.
    func labelKey(kind: TaskKind) -> String { "field.\(kind.rawValue).\(id)" }
}

/// DATA_MODEL §2.1.
enum AmbiguityKind: String, Codable, Sendable, Hashable, CaseIterable {
    case contact, date, place, phoneNumber, other
}

/// DATA_MODEL §2.1. `.contact` / `.phoneNumber` candidates are built on device only (D-056).
struct Ambiguity: Codable, Sendable, Hashable {
    var kind: AmbiguityKind
    var question: String             // Vietnamese, one short sentence
    var candidates: [Candidate]      // empty → free-text answer
}

/// DATA_MODEL §2.1.
struct Candidate: Codable, Sendable, Hashable, Identifiable {
    let id: String                   // value to put into Field.value if chosen
    var title: String
    var subtitle: String?            // masked number / formatted date
    var imageRef: String?            // 🔒 contact thumbnail identifier, device only
}
