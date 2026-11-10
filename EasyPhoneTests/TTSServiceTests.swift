import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.3 — ARCHITECTURE §4.3 (TTSService), spec §6.2 AC5, UI_SCREENS S15 "Nghe thử", DATA_MODEL §5 `speechRate`.
@MainActor
@Suite("TTSService (spec §6.2 AC5)")
struct TTSServiceTests {
    @Test func settingsTestVoiceSpeaksSampleAtChosenRate() async {
        let tts = MockTTSService()
        let local = MockLocalDataRepository()
        let vm = SettingsViewModel(localData: local, drafts: MockTaskRepository(),
                                   auth: MockAuthService(initial: .signedOut), tts: tts)
        vm.settings.speechRate = 0.38
        await vm.testVoice()
        #expect(tts.spoken.count == 1)
        #expect(tts.spoken.first?.text == "Xin chào, mình là EasyPhoneK.")
        #expect(tts.spoken.first?.rate == 0.38)
        vm.stopVoice()
        #expect(tts.stopCount == 1)
    }

    @Test func defaultRateIsDataModelDefault() {
        #expect(MockLocalDataRepository().settings().speechRate == 0.45)
    }

    @Test func environmentsProvideTTS() {
        #expect(AppEnvironment.mock().tts is MockTTSService)
    }

    /// The live service on the Simulator: stop() right after speak() must return promptly (AC5 "immediately").
    @Test func liveStopEndsSpeakPromptly() async {
        let tts = LiveTTSService()
        let start = ContinuousClock.now
        async let done: Void = tts.speak("Xin chào, mình là EasyPhoneK. Đây là một câu khá dài để kiểm tra nút dừng.", rate: 0.45)
        try? await Task.sleep(for: .milliseconds(300))
        tts.stop()
        await done
        #expect(ContinuousClock.now - start < .seconds(3))
    }
}
