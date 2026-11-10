import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.4a — UI_SCREENS S03 modes 1–2, spec §6.2 AC1 / AC5, API_CONTRACT §7.4 (never auto-send), D-104.
@MainActor
@Suite("Conversation listen + transcript (UI_SCREENS S03)")
struct ConversationTests {
    let repo = MockTaskRepository()
    let speech = MockSpeechService()
    let tts = MockTTSService()
    let local = MockLocalDataRepository()

    func model(draftId: UUID? = nil) -> ConversationViewModel {
        ConversationViewModel(draftId: draftId, repository: repo, speech: speech, tts: tts, localData: local)
    }

    @Test func micEntryListensThenShowsEditableTranscriptAndSavesDraft() async throws {
        let vm = model()
        await vm.onAppear()
        #expect(speech.startCount == 1)
        #expect(speech.lastLocale?.identifier == "vi-VN")
        #expect(vm.mode == .transcript)
        #expect(vm.text == "Nhắc tôi 8 giờ sáng mai uống thuốc")
        #expect(vm.noticeKey == nil)
        let id = try #require(vm.draftId)                                    // D-104: saved as soon as there is text
        #expect(repo.draft(id)?.originalInput == vm.text)
        #expect(repo.draft(id)?.inputMode == .voice)
        #expect(repo.draft(id)?.steps.isEmpty == true)
    }

    @Test func listeningStopsReadingFirst() async {
        let vm = model()
        await vm.onAppear()
        Task { await vm.toggleReading() }
        await Task.yield()
        await vm.speakAgain()                                                // AC5: TTS stops when listening starts
        #expect(tts.spoken.count == 1)
        #expect(!vm.isReading)
    }

    @Test func editsAutosave() async throws {
        let vm = model()
        await vm.onAppear()
        vm.text = "Nhắc tôi 9 giờ sáng mai uống thuốc"
        let id = try #require(vm.draftId)
        let draft = try #require(repo.draft(id))
        #expect(draft.originalInput == "Nhắc tôi 9 giờ sáng mai uống thuốc")
    }

    @Test func unavailableShowsKeyboardMessageAndCreatesNothing() async {
        speech.script = []
        speech.error = .unavailable("speech.vi.unavailable")
        let vm = model()
        await vm.onAppear()
        #expect(vm.mode == .transcript)
        #expect(vm.noticeKey == "conv.speech.unavailable")
        #expect(vm.draftId == nil && repo.saveCount == 0)
        #expect(UserMessage(key: "conv.speech.unavailable").text == "Máy chưa nghe được tiếng Việt lúc này. Bạn gõ chữ nhé.")
    }

    @Test func emptyRecordingAsksAgain() async {
        speech.script = [Transcript(text: "", isFinal: true)]
        let vm = model()
        await vm.onAppear()
        #expect(vm.noticeKey == "conv.speech.empty")
        #expect(UserMessage(key: "conv.speech.empty").text == "Mình chưa nghe rõ. Bạn nói lại hoặc gõ chữ nhé.")
    }

    @Test func failedRetryKeepsPreviousText() async throws {
        let draft = TaskDraft(inputMode: .text, originalInput: "Gọi cho mẹ")
        repo.save(draft)
        let vm = model(draftId: draft.id)
        await vm.onAppear()
        #expect(speech.startCount == 0)                                      // saved draft → transcript, no auto-listen
        #expect(vm.mode == .transcript && vm.text == "Gọi cho mẹ")
        speech.script = [Transcript(text: "", isFinal: true)]
        await vm.speakAgain()
        #expect(vm.text == "Gọi cho mẹ")
        #expect(vm.noticeKey == "conv.speech.empty")
        #expect(repo.draft(draft.id)?.originalInput == "Gọi cho mẹ")         // never wiped (D-104)
    }

    @Test func sendNeedsTextAndNeverHappensAlone() async {
        speech.script = []
        let vm = model()
        await vm.onAppear()
        #expect(!vm.canSend)
        #expect(!vm.send())
        vm.text = "Gọi cho mẹ"
        #expect(vm.canSend)
        #expect(vm.send())
        #expect(repo.draft(vm.draftId!)?.originalInput == "Gọi cho mẹ")
    }

    @Test func readAloudUsesSettingsRate() async {
        local.settings().speechRate = 0.4
        let vm = model()
        await vm.onAppear()
        await vm.toggleReading()
        #expect(tts.spoken.first?.text == "Nhắc tôi 8 giờ sáng mai uống thuốc")
        #expect(tts.spoken.first?.rate == 0.4)
    }

    // MARK: - Owner report 2026-11-10 + auto-stop (DOC-29)

    func fastModel() -> ConversationViewModel {
        ConversationViewModel(draftId: nil, repository: repo, speech: speech, tts: tts, localData: local,
                              silenceAfterSpeech: .milliseconds(50), noSpeechTimeout: .milliseconds(80))
    }

    @Test func emptyFinalAfterStopKeepsHeardWords() async {
        speech.script = [Transcript(text: "Gọi cho mẹ", isFinal: false), Transcript(text: "", isFinal: true)]
        let vm = model()
        await vm.onAppear()
        #expect(vm.text == "Gọi cho mẹ")
        #expect(vm.noticeKey == nil)
        #expect(repo.draft(vm.draftId!)?.originalInput == "Gọi cho mẹ")
    }

    @Test func silenceAfterSpeechStopsByItself() async {
        speech.script = [Transcript(text: "Gọi", isFinal: false), Transcript(text: "Gọi cho mẹ", isFinal: false)]
        speech.holdsUntilStop = true
        let vm = fastModel()
        await vm.onAppear()                                              // returns only after the auto-stop
        #expect(speech.stopCount == 1)
        #expect(vm.mode == .transcript)
        #expect(vm.text == "Gọi cho mẹ")
        #expect(vm.canSend)                                              // waits for "Gửi", never auto-sent
    }

    @Test func noSpeechStopsAndAsksAgain() async {
        speech.script = []
        speech.holdsUntilStop = true
        let vm = fastModel()
        await vm.onAppear()
        #expect(speech.stopCount == 1)
        #expect(vm.noticeKey == "conv.speech.empty")
    }

    @Test func leavingStopsMicAndVoice() async {
        let vm = model()
        vm.onDisappear()
        await Task.yield()
        #expect(tts.stopCount == 1)
    }
}
