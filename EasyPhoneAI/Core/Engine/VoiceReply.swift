import Foundation

/// Hands-free answers (D-312): what a short spoken reply means. Pure, unit-tested.
enum VoiceReply: Equatable, Sendable {
    /// "đồng ý", "có", "ok", "làm đi", "xác nhận", "được", "vâng", "dạ"
    case yes
    /// "sửa", "đổi" — the user edits on screen
    case edit
    /// "thôi", "dừng", "hủy", "không" — nothing runs, listening stops
    case stop
    case other

    static func classify(_ text: String) -> VoiceReply {
        let words = NameNormalizer.normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 6 else { return .other }   // a long sentence is not a yes / no
        let joined = " " + words.joined(separator: " ") + " "
        if stopWords.contains(where: joined.contains) { return .stop }       // "không đồng ý" is a stop, checked first
        if editWords.contains(where: joined.contains) { return .edit }
        if yesWords.contains(where: joined.contains) { return .yes }
        return .other
    }

    // Diacritics folded ("đồng ý" → "dong y", "hủy" → "huy").
    private static let stopWords = [" thoi ", " dung ", " huy ", " khong ", " dung lai ", " bo qua "]
    private static let editWords = [" sua ", " doi ", " chinh "]
    private static let yesWords = [" dong y ", " co ", " ok ", " oke ", " okay ", " lam di ", " xac nhan ", " duoc ",
                              " vang ", " da ", " u ", " uh ", " lam luon "]
}

/// One short listening turn for S04 (D-312): ends 2 s after the last words or after `noSpeech` without any word.
@MainActor enum ListenOnce {
    static func listen(_ speech: any SpeechService, locale: Locale = Locale(identifier: "vi-VN"),
                       noSpeech: Duration = .seconds(8), silence: Duration = .milliseconds(1500)) async -> String {
        var heard = ""
        var timer: Task<Void, Never>?
        func arm(_ delay: Duration) {
            timer?.cancel()
            timer = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await speech.stop()
            }
        }
        arm(noSpeech)
        do {
            for try await transcript in speech.start(locale: locale) where !transcript.text.isEmpty {
                heard = SpeechCleanup.fix(transcript.text)                      // D-322
                arm(silence)
            }
        } catch {
            // Permission / recognizer failure: nothing heard; the screen still works by tap.
        }
        timer?.cancel()
        return heard
    }
}
