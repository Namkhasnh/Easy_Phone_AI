import AVFoundation
import OSLog

/// `AVSpeechSynthesizer` with a vi-VN voice (DECISIONS §2.1, D-055). Text never leaves the phone.
@MainActor final class LiveTTSService: NSObject, TTSService {
    private let synthesizer = AVSpeechSynthesizer()
    /// One waiter per utterance; resumed on finish or cancel.
    private var waiters: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Double) async {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        // TODO(spec): no fallback is specified when the phone has no vi-VN voice; the system default voice is used.
        if let voice = AVSpeechSynthesisVoice(language: "vi-VN") {
            utterance.voice = voice
        } else {
            Self.logger.info("tts: no vi-VN voice installed")
        }
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
