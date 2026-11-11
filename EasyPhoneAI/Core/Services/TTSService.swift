import Foundation

/// Text-to-speech, vi-VN on device (ARCHITECTURE §4.3, D-055). `@MainActor` because it owns the audio session (§8).
/// Always stoppable (spec §6.2 AC5): `stop()` cuts the voice off immediately; callers stop it when listening starts.
@MainActor protocol TTSService: AnyObject, Sendable {
    /// Speaks `text` and returns when it finished or was stopped. A new call stops the current one first.
    /// `rate` = `AppSettings.speechRate` (`AVSpeechUtterance` scale, DATA_MODEL §5).
    func speak(_ text: String, rate: Double) async
    func stop()
}
