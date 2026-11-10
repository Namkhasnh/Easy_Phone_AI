import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.2 — ARCHITECTURE §4.3 (SpeechService), API_CONTRACT §7.4 (60 s), D-055, D-186, D-249.
@MainActor
@Suite("SpeechService (ARCHITECTURE §4.3)")
struct SpeechServiceTests {
    @Test func confidenceIsAverageAndNilForPartials() {
        #expect(Transcript.averageConfidence([]) == nil)
        #expect(Transcript.averageConfidence([0, 0, 0]) == nil)          // Speech reports 0 on partial results
        let avg = try! #require(Transcript.averageConfidence([0.9, 0.7]))
        #expect(abs(avg - 0.8) < 0.0001)
    }

    @Test func mockStreamsPartialsThenFinal() async throws {
        let speech = MockSpeechService()
        var got: [Transcript] = []
        for try await t in speech.start(locale: Locale(identifier: "vi-VN")) { got.append(t) }
        #expect(got.map(\.isFinal) == [false, true])
        #expect(got.last?.text == "Nhắc tôi 8 giờ sáng mai uống thuốc")
        #expect(speech.lastLocale?.identifier == "vi-VN")
        #expect(speech.startCount == 1)
    }

    @Test func mockUnavailableEndsWithStableCode() async {
        let speech = MockSpeechService()
        speech.script = []
        speech.error = .unavailable("speech.vi.unavailable")
        speech.audio = Data([1, 2, 3])
        await #expect(throws: ServiceError.unavailable("speech.vi.unavailable")) {
            for try await _ in speech.start(locale: Locale(identifier: "vi-VN")) {}
        }
        #expect(await speech.recordedAudio() == Data([1, 2, 3]))         // fallback audio for /v1/transcribe
        #expect(UserMessage(key: "error.speech.vi.unavailable").text == "Máy chưa nghe được tiếng Việt lúc này. Bạn gõ chữ nhé.")
    }

    @Test func sessionLimitMatchesTranscribeLimit() {
        #expect(SpeechLimits.maxDuration == .seconds(60))
    }

    @Test func usageDescriptionsArePresent() {
        // Without these keys iOS kills the app when the mic opens (D-186).
        for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"] {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
            #expect(value?.isEmpty == false, "\(key)")
        }
    }

    @Test func environmentsProvideSpeech() {
        #expect(AppEnvironment.mock().speech is MockSpeechService)
    }
}
