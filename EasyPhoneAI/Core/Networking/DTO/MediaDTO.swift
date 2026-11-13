import Foundation

/// The `meta` part of the media uploads (`/v1/ocr`, `/v1/transcribe`) = backend `schemas/media.py`.
struct MediaMeta: Codable, Sendable, Hashable {
    var schemaVersion: Int = 1
    var locale: String          // "vi-VN" or "en-US"

    static let vietnamese = MediaMeta(locale: "vi-VN")
}

/// `POST /v1/transcribe` response (API_CONTRACT §7.4). `confidence` 0–1 or `nil` (D-238).
/// The text is always shown as editable and never sent to `/v1/parse` by itself (spec §6.2 AC1).
struct TranscribeResponse: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let requestId: String
    let text: String
    let confidence: Double?
}

/// `POST /v1/ocr` response (API_CONTRACT §7.3). `box` = Vision space (0–1, bottom-left), `text` = lines joined by "\n".
/// The text is untrusted (AI_PROMPTS §2.2): shown and sent to `/v1/extract` only, never acted on.
struct OCRResponse: Codable, Sendable, Hashable {
    struct Line: Codable, Sendable, Hashable {
        let text: String
        let box: OCRBox
    }

    let schemaVersion: Int
    let requestId: String
    let text: String
    let lines: [Line]
}
