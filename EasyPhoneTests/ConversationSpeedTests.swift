import Foundation
import Testing
@testable import EasyPhoneAI

/// D-320 — speed: on-device reminders / events, shorter end-of-speech wait, instant spoken acknowledgement.
@MainActor
@Suite("Conversation speed (D-320)")
struct ConversationSpeedTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-19T10:00:00+07:00")!

    func vm(_ text: String, input: InputMode, repo: MockTaskRepository, api: MockAPIClient, tts: MockTTSService)
        -> (ConversationViewModel, TaskDraft) {
        let draft = TaskDraft(inputMode: input, originalInput: text, timeZoneId: "Asia/Ho_Chi_Minh")
        repo.save(draft)
        let vm = ConversationViewModel(draftId: draft.id, repository: repo, speech: MockSpeechService(), api: api,
                                       tts: tts, localData: MockLocalDataRepository(),
                                       engine: TaskEngine(repository: repo), now: { Self.now })
        return (vm, draft)
    }

    /// Typed drafts are sent on appear; spoken ones when listening ends (`send()`, as auto-send does).
    func start(_ vm: ConversationViewModel, _ input: InputMode) async {
        await vm.onAppear()
        if input == .voice { await vm.send() }
    }

    @Test func aReminderWithAClearTimeNeverCallsTheAI() async throws {
        let repo = MockTaskRepository(), api = MockAPIClient(), tts = MockTTSService()
        let (vm, draft) = vm("nhắc tôi uống thuốc lúc 8 giờ tối", input: .voice, repo: repo, api: api, tts: tts)
        await start(vm, .voice)
        #expect(api.parseCalls.isEmpty && !vm.acknowledged)                    // no AI, no unit, nothing to wait for
        let step = try #require(repo.draft(draft.id)?.steps.first)
        #expect(step.kind == .reminder && step.operation == .create)
        #expect(step.field("title")?.value == "Uống thuốc")
        #expect(step.field("dueDate")?.value == "2026-11-19T20:00:00+07:00")
    }

    @Test func aGuessedHourIsHighlightedLikeTheAIDoes() async throws {
        let repo = MockTaskRepository(), api = MockAPIClient(), tts = MockTTSService()
        let (vm, draft) = vm("mai 3 giờ họp", input: .text, repo: repo, api: api, tts: tts)
        await vm.onAppear()
        let step = try #require(repo.draft(draft.id)?.steps.first)
        #expect(step.kind == .calendarEvent && step.field("startDate")?.value == "2026-11-20T15:00:00+07:00")
        #expect(step.field("startDate")?.confidence == 0.6)
    }

    @Test func spokenAIRequestsAreAcknowledgedAtOnceTypedOnesAreNot() async {
        for (input, expected) in [(InputMode.voice, true), (.text, false)] {
            let repo = MockTaskRepository(), api = MockAPIClient(), tts = MockTTSService()
            let (vm, _) = vm("thứ Bảy 9 giờ đi khám răng", input: input, repo: repo, api: api, tts: tts)
            await start(vm, input)
            #expect(api.parseCalls.count == 1)
            #expect(vm.acknowledged == expected)
            #expect(tts.spoken.contains { $0.text == "Để Khoai xem nhé." } == expected)
        }
    }

    @Test func shorterWaitOnlyForRequestsThePhoneUnderstands() {
        let repo = MockTaskRepository(), api = MockAPIClient(), tts = MockTTSService()
        let (vm, _) = vm("", input: .voice, repo: repo, api: api, tts: tts)
        #expect(vm.silenceDelay(for: "nhắc tôi uống thuốc lúc 8 giờ tối") == .milliseconds(1000))
        #expect(vm.silenceDelay(for: "gọi cho mẹ") == .milliseconds(1000))
        #expect(vm.silenceDelay(for: "nhắc tôi uống") == .milliseconds(1500))           // not finished yet
        #expect(vm.silenceDelay(for: "thứ Bảy 9 giờ đi khám") == .milliseconds(1500))   // AI request
    }
}
