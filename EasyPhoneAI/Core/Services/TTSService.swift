import Foundation

/// Text-to-speech, vi-VN on device (ARCHITECTURE §4.3, D-055). `@MainActor` because it owns the audio session (§8).
/// Always stoppable (spec §6.2 AC5): `stop()` cuts the voice off immediately; callers stop it when listening starts.
@MainActor protocol TTSService: AnyObject, Sendable {
    /// Speaks `text` and returns when it finished or was stopped. A new call stops the current one first.
    /// `rate` = `AppSettings.speechRate` (`AVSpeechUtterance` scale, DATA_MODEL §5).
    func speak(_ text: String, rate: Double) async
    func stop()
    /// D-324: the Vietnamese voices installed on this phone (S15 Giọng nói → "Giọng đọc").
    func vietnameseVoices() -> [TTSVoice]
}

/// One installed voice (no AVFoundation type in Views, D-015).
struct TTSVoice: Sendable, Hashable, Identifiable {
    enum Quality: Int, Sendable { case standard, enhanced, premium }
    let id: String          // `AVSpeechSynthesisVoice.identifier`
    let name: String        // "Linh"
    let quality: Quality
}

/// D-324: what `speak` uses besides the rate. Read at every utterance, so a change applies at once.
struct TTSPreferences: Sendable, Hashable {

    var voiceId: String?    // nil = the iPhone's default vi-VN voice
    var pitch: Double = 1.0 // `AVSpeechUtterance.pitchMultiplier`
}
