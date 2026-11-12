import Foundation

/// `POST /v1/extract` request (API_CONTRACT §7.2). `ocrText` is the photo's text (untrusted, D-057); the backend wraps it.
/// `now` is a string with the device offset (D-058), like `ParseRequest`.
struct ExtractRequest: Codable, Sendable, Hashable {
    var schemaVersion: Int = 1
    var ocrText: String
    var now: String
    var timezone: String
    var locale: String
}

/// `POST /v1/extract` response. `span` = UTF-16 offsets into `ocrText` (DATA_MODEL §1.7) or null (not found,
/// then `confidence ≤ 0.5`). `id` ∈ title, dateTime, address, personName, phoneNumber (catalog `ocr`).
struct ExtractResponse: Codable, Sendable, Hashable {
    struct Span: Codable, Sendable, Hashable {
        let start: Int
        let end: Int
    }

    struct ExtractedField: Codable, Sendable, Hashable {
        let id: String
        let value: String
        let confidence: Double
        let span: Span?
    }

    let schemaVersion: Int
    let requestId: String
    let fields: [ExtractedField]
    /// calendarEvent, reminder, copyContactInfo, ride (Phase 3) or nil.
    let suggestedNextAction: String?
}
