import Foundation

/// One update from `SpeechService.start` (ARCHITECTURE §4.3): partial transcripts while the user speaks, then one final.
// TODO(spec): ARCHITECTURE §4.3 names `Transcript` but defines no fields; text + isFinal + confidence chosen here.
struct Transcript: Sendable, Hashable {
    /// Full text recognized so far (not a delta). Always shown editable, never auto-sent (spec §6.2 AC1, API_CONTRACT §7.4).
    let text: String
    let isFinal: Bool
    /// 0–1 average over the recognized segments; `nil` when the recognizer gives no score (partials).
    /// The ViewModel may fall back to `/v1/transcribe` when it is low (ARCHITECTURE §4.3).
    let confidence: Double?

    init(text: String, isFinal: Bool, confidence: Double? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
    }

    /// Average of per-segment scores; Speech reports 0 for every segment of a partial result → `nil`.
    static func averageConfidence(_ scores: [Float]) -> Double? {
        guard !scores.isEmpty, scores.contains(where: { $0 > 0 }) else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }
}
