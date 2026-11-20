import Testing
@testable import EasyPhoneAI

/// D-324 — Khoai's voice and pitch (S15 Giọng nói).
@MainActor
@Suite("Voice choice (D-324)")
struct VoiceChoiceTests {
    @Test func choiceIsSavedAndAMissingVoiceFallsBackToDefault() {
        let local = MockLocalDataRepository()
        let tts = MockTTSService()
        tts.voices = [TTSVoice(id: "vi.linh.enhanced", name: "Linh", quality: .enhanced),
                      TTSVoice(id: "vi.linh", name: "Linh", quality: .standard)]
        let vm = SettingsViewModel(localData: local, drafts: MockTaskRepository(), auth: MockAuthService(), tts: tts)
        vm.loadVoices()
        #expect(vm.voices.count == 2 && vm.selectedVoiceId == nil)               // default: iPhone voice
        vm.selectedVoiceId = "vi.linh.enhanced"
        #expect(local.settings().ttsVoiceId == "vi.linh.enhanced")
        tts.voices = []                                                           // voice deleted from the phone
        vm.loadVoices()
        #expect(vm.selectedVoiceId == nil)
    }

    @Test func labelsShowTheQuality() {
        #expect(SettingsViewModel.voiceLabel(TTSVoice(id: "a", name: "Linh", quality: .enhanced)) == "Linh (nâng cao)")
        #expect(SettingsViewModel.voiceLabel(TTSVoice(id: "b", name: "Linh", quality: .premium)) == "Linh (cao cấp)")
        #expect(SettingsViewModel.voiceLabel(TTSVoice(id: "c", name: "Linh", quality: .standard)) == "Linh")
    }

    @Test func defaultsKeepTheOldVoice() {
        let s = MockLocalDataRepository().settings()
        #expect(s.ttsVoiceId == nil && s.ttsPitch == 1.0)
    }

    @Test func spokenContentChoiceSurvivesAnEmptyVoiceList() {
        let local = MockLocalDataRepository()
        let tts = MockTTSService()
        tts.voices = []
        let vm = SettingsViewModel(localData: local, drafts: MockTaskRepository(), auth: MockAuthService(), tts: tts)
        vm.loadVoices()
        vm.selectedVoiceId = TTSPreferences.spokenContentVoiceId
        #expect(vm.selectedVoiceId == TTSPreferences.spokenContentVoiceId)    // not an installed voice, still kept
    }
}
