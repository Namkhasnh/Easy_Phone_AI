import Foundation

/// The `meta` part of the media uploads (`/v1/transcribe` now, `/v1/ocr` in 1D) = backend `schemas/media.py`.
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
