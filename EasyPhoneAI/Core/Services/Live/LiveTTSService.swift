import AVFoundation
import OSLog

/// `AVSpeechSynthesizer` with a vi-VN voice (DECISIONS §2.1, D-055). Text never leaves the phone.
@MainActor final class LiveTTSService: NSObject, TTSService {
    private let synthesizer = AVSpeechSynthesizer()
    /// One waiter per utterance; resumed on finish or cancel.
    private var waiters: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private let preferences: @MainActor () -> TTSPreferences

    init(preferences: @escaping @MainActor () -> TTSPreferences = { TTSPreferences() }) {
        self.preferences = preferences
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Double) async {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        // TODO(spec): no fallback is specified when the phone has no vi-VN voice; the system default voice is used.
        let prefs = preferences()
        // Siri voices are not available to apps, not even through `prefersAssistiveTechnologySettings` (tried on the
        // owner's iPhone 2026-11-20). Default = the best installed vi voice (Linh Nâng cao when downloaded).
        if let id = prefs.voiceId, let chosen = AVSpeechSynthesisVoice(identifier: id) {   // D-324
            utterance.voice = chosen
        } else if let best = Self.bestVietnameseVoice() {
            utterance.voice = best
        } else if let voice = AVSpeechSynthesisVoice(language: "vi-VN") {
            utterance.voice = voice
        } else {
            Self.logger.info("tts: no vi-VN voice installed")
        }
        utterance.pitchMultiplier = Float(min(max(prefs.pitch, 0.5), 2.0))
        utterance.rate = Float(min(max(rate, Double(AVSpeechUtteranceMinimumSpeechRate)),
                                   Double(AVSpeechUtteranceMaximumSpeechRate)))

        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? audio.setActive(true)

        let key = ObjectIdentifier(utterance)
        await withCheckedContinuation { continuation in
            waiters[key] = continuation
            synthesizer.speak(utterance)
        }
        if waiters.isEmpty && !synthesizer.isSpeaking {
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    static func bestVietnameseVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("vi") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    func vietnameseVoices() -> [TTSVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("vi") }
            .map { v in
                TTSVoice(id: v.identifier, name: v.name,
                         quality: v.quality == .premium ? .premium : v.quality == .enhanced ? .enhanced : .standard)
            }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// AC5: immediate, not at the next word.
    func stop() {
        guard synthesizer.isSpeaking || !waiters.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    fileprivate func finished(_ key: ObjectIdentifier) {
        waiters.removeValue(forKey: key)?.resume()
    }

    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "tts")
}

extension LiveTTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(key) }
    }
}
