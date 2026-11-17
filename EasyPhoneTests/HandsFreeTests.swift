import Foundation
import Testing
@testable import EasyPhoneAI

/// 1H.1 — hands-free conversation (D-312, D-108, D-299, D-305): spoken "đồng ý" on S04 for safe steps only,
/// follow-up questions read aloud then the mic opens again.
@MainActor
@Suite("Hands-free (D-312)")
struct HandsFreeTests {
    let repo = MockTaskRepository()
    let local = MockLocalDataRepository()

    @Test func replies() {
        for text in ["Đồng ý", "có", "ok làm đi", "vâng", "xác nhận nhé"] { #expect(VoiceReply.classify(text) == .yes, "\(text)") }
        for text in ["sửa", "đổi giờ"] { #expect(VoiceReply.classify(text) == .edit, "\(text)") }
        for text in ["thôi", "dừng lại", "hủy", "không đồng ý", "không"] { #expect(VoiceReply.classify(text) == .stop, "\(text)") }
        for text in ["", "ờ để tôi nghĩ xem đã nào bạn ơi", "mai"] { #expect(VoiceReply.classify(text) == .other, "\(text)") }
    }

    func review(kind: TaskKind = .reminder, operation: TaskOperation = .create, inputMode: InputMode = .voice,
                heard: String, values: [String: String] = ["title": "Uống thuốc", "dueDate": "2026-12-01T08:00:00+07:00"])
        -> (ReviewViewModel, MockTTSService, MockSpeechService, MockRemindersService) {
        let reminders = MockRemindersService()
        let perms = MockPermissionManager()
        perms.set(.reminders, .granted)
        let e = TaskEngine(repository: repo, executors: [.reminder: RemindersExecutor(reminders: reminders, permissions: perms,
                                                                                         morningHour: { 8 })],
                           now: { Validator.parseDateTime("2026-11-18T09:00:00+07:00")! })
        let fields = FieldCatalog.mvp.fields(kind, operation).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        var step = TaskStep(order: 0, kind: kind, operation: operation, fields: fields)
        if operation == .delete { step.targetRef = "ek:reminder:1" }
        let d = TaskDraft(inputMode: inputMode, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step])
        repo.save(d)
        e.revalidate(stepId: d.steps[0].id, in: d)
        let tts = MockTTSService()
        let speech = MockSpeechService()
        speech.script = [Transcript(text: heard, isFinal: true, confidence: 0.9)]
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: perms, localData: local,
                                 tts: tts, speech: speech)
        return (vm, tts, speech, reminders)
    }

    @Test func spokenYesConfirmsASafeStep() async {
        let (vm, tts, speech, _) = review(heard: "đồng ý")
        #expect(vm.step?.state == .awaitingApproval && vm.canVoiceConfirm)
        vm.startHandsFreeIfAllowed()
        await vm.waitForHandsFree()
        #expect(speech.startCount == 1)
        #expect(tts.spoken.first?.text.hasPrefix(vm.spokenSummary) == true)
        #expect(tts.spoken.first?.text.hasSuffix(UserMessage(key: "review.voice.prompt").text) == true)
        #expect(vm.step?.state == .succeeded)
        #expect(tts.spoken.count == 2)                                             // the result is read too
    }

    @Test func stopOrOtherWordsRunNothing() async {
        for heard in ["thôi", "sửa", "", "để mai tính"] {
            let (vm, _, _, _) = review(heard: heard)
            vm.startHandsFreeIfAllowed()
            await vm.waitForHandsFree()
            #expect(vm.step?.state == .awaitingApproval, "\(heard)")
        }
    }

    @Test func deleteNeverByVoice() async {                                       // D-108
        let (vm, tts, speech, _) = review(operation: .delete, heard: "đồng ý", values: ["title": "Uống thuốc"])
        vm.startHandsFreeIfAllowed()
        await vm.waitForHandsFree()
        #expect(speech.startCount == 0)
        #expect(tts.spoken.first?.text.hasSuffix(UserMessage(key: "review.voice.tapNeeded").text) == true)
        #expect(vm.step?.state != .succeeded)
    }

    @Test func typedRequestsAndTheToggleOffStaySilent() async {
        let (typed, tts1, _, _) = review(inputMode: .text, heard: "đồng ý")
        typed.startHandsFreeIfAllowed()
        await typed.waitForHandsFree()
        #expect(tts1.spoken.isEmpty && typed.step?.state == .awaitingApproval)

        local.settings().handsFree = false
        let (off, tts2, _, _) = review(heard: "đồng ý")
        off.startHandsFreeIfAllowed()
        await off.waitForHandsFree()
        #expect(tts2.spoken.isEmpty && off.step?.state == .awaitingApproval)
    }

    @Test func gmailDraftIsVoiceConfirmableButNotUpdates() {
        #expect(ReviewViewModel.isVoiceConfirmable(.emailReply, .create))
        #expect(ReviewViewModel.isVoiceConfirmable(.calendarEvent, .create))
        for (kind, op) in [(TaskKind.calendarEvent, TaskOperation.update), (.calendarEvent, .delete),
                           (.reminder, .complete), (.reminder, .snooze), (.reminder, .delete)] {
            #expect(!ReviewViewModel.isVoiceConfirmable(kind, op))
        }
    }

    @Test func strings() {
        for key in ["settings.handsFree", "settings.handsFree.note", "review.voice.prompt", "review.voice.tapNeeded",
                    "review.voice.listening", "review.voice.stop"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
        #expect(AppSettings().handsFree)                                           // default on
    }
}
