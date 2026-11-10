import Foundation

/// `POST /v1/parse` wire models (API_CONTRACT §7.1, DATA_MODEL §6.2) = backend `schemas/parse.py`.
///
/// `ParsedDraft` = the LLM output `ParsedDraftLLM` (`task_draft.json`) + `schemaVersion` + `requestId` (D-277).
/// `kind`, `operation`, field `id` and `unsupported.reason` stay raw strings here so an unknown value never
/// breaks decoding; `DraftBuilder` (1B.13) maps them to `TaskKind` / `TaskOperation` and drops what it can't.
/// No 🔒 key (`contactId`, `phoneNumber` of a contact, `targetRef`, `calendarId`, …) exists in these types (D-056).
struct ParsedDraft: Codable, Sendable, Hashable {
    var schemaVersion: Int
    var requestId: String?
    var steps: [ParsedStep]
    var followUpQuestion: String?
    var unsupported: ParsedUnsupported?

    // Nulls are written out: the backend requires every key (`extra="forbid"`, no defaults).
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(steps, forKey: .steps)
        try c.encode(followUpQuestion, forKey: .followUpQuestion)
        try c.encode(unsupported, forKey: .unsupported)
    }
}

struct ParsedStep: Codable, Sendable, Hashable {
    var kind: String
    var operation: String
    var fields: [ParsedField]
    var dateCandidates: [ParsedDateCandidate]
}

struct ParsedField: Codable, Sendable, Hashable {
    var id: String
    var value: String?
    var confidence: Double?
    var sourceQuote: String?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(value, forKey: .value)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(sourceQuote, forKey: .sourceQuote)
    }
}

struct ParsedDateCandidate: Codable, Sendable, Hashable {
    var fieldId: String
    var value: String       // ISO 8601 with offset
    var label: String       // Vietnamese, e.g. "Thứ Sáu 13/11" (data from the backend, may be shown)
}

/// `reason` ∈ recurringEvent, invitation, emailSend, booking, payment, multiPageOcr, bulkAction, phaseNotEnabled, other.
struct ParsedUnsupported: Codable, Sendable, Hashable {
    var reason: String
    var message: String
}

/// Request body. `now` is a string because it must keep the device offset (`+07:00`, D-058);
/// `JSONEncoder.iso8601` would write UTC `Z`.
struct ParseRequest: Codable, Sendable, Hashable {
    var schemaVersion: Int = 1
    var text: String
    var inputMode: InputMode
    var now: String
    var timezone: String
    var locale: String
    var savedPlaceLabels: [String]     // labels only, never addresses (DATA_MODEL §5)
    var context: ParseContext

    struct ParseContext: Codable, Sendable, Hashable {
        var draftId: UUID?
        var answeringFieldId: String?
        var currentDraft: ParsedDraft?

        static let none = ParseContext(draftId: nil, answeringFieldId: nil, currentDraft: nil)

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            // Lowercase UUID: Swift's `uuidString` is uppercase; the backend accepts both, fixtures use lowercase.
            try c.encode(draftId?.uuidString.lowercased(), forKey: .draftId)
            try c.encode(answeringFieldId, forKey: .answeringFieldId)
            try c.encode(currentDraft, forKey: .currentDraft)
        }
    }

    /// `2026-11-08T18:07:00+07:00` in `timeZone` (seconds, offset kept).
    static func nowString(_ date: Date, in timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
