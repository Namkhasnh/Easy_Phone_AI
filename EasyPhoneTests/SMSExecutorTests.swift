import Foundation
import MessageUI
import Testing
@testable import EasyPhoneAI

/// 1C.11 — ARCHITECTURE §5.3, spec §6.8 AC2 / AC4, D-102, D-103, D-222.
@MainActor
@Suite("SMSExecutor + composer")
struct SMSExecutorTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    let repo = MockTaskRepository()

    func review(channel: String = "sms", canSend: Bool = true) -> ReviewViewModel {
        let e = TaskEngine(repository: repo, executors: [.sms: SMSExecutor(messages: MockMessagesService(canSendText: canSend))],
                           serviceIds: ["zalo"], now: { Self.now })
        let values = ["recipientName": "mẹ", "contactId": "lan", "phoneNumber": "+84903333444",
                      "body": "Con về muộn nhé", "channel": channel]
        let fields = FieldCatalog.mvp.fields(.sms, .open).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh",
                          steps: [TaskStep(order: 0, kind: .sms, operation: .open, fields: fields)])
        repo.save(d)
        e.revalidate(stepId: d.steps[0].id, in: d)
        return ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: MockPermissionManager())
    }

    @Test func confirmOpensThePrefilledComposerAndSentSucceeds() async {
        let vm = review()
        await vm.confirm()
        #expect(vm.pendingComposer?.recipients == ["+84903333444"])
        #expect(vm.pendingComposer?.body == "Con về muộn nhé")
        #expect(vm.step?.state == .processing)                                  // nothing sent by the app (D-103)
        vm.composerFinished(.sent)
        #expect(vm.pendingComposer == nil)
        #expect(vm.step?.state == .succeeded)
        #expect(vm.step?.resultEvidence == "msg:sent:2026-11-10T09:00:00+07:00")
    }

    @Test func cancelledGoesBackToReview() async {                               // D-222
        let vm = review()
        await vm.confirm()
        vm.composerFinished(.cancelled)
        #expect(vm.step?.state == .awaitingApproval && vm.step?.resultEvidence == nil)
        vm.composerFinished(.sent)                                               // late / duplicate callback ignored
        #expect(vm.step?.state == .awaitingApproval)
    }

    @Test func failedIsFailed() async {
        let vm = review()
        await vm.confirm()
        vm.composerFinished(.failed)
        #expect(vm.step?.state == .failed && vm.step?.resultEvidence == nil)
    }

    @Test func deviceThatCannotSendFails() async {
        let vm = review(canSend: false)
        await vm.confirm()
        #expect(vm.pendingComposer == nil && vm.step?.state == .failed)
        #expect(vm.errorMessage(vm.step!) == "Điện thoại này chưa gửi được tin nhắn. Bạn có thể sao chép nội dung.")
    }

    @Test func otherChannelIsNotTheComposer() async {
        let vm = review(channel: "zalo")
        await vm.confirm()
        #expect(vm.pendingComposer == nil)                                       // copy path = 1C.12
    }

    @Test func onlySentMapsToSent() {
        #expect(MessageComposerView.Coordinator.map(.sent) == .sent)
        #expect(MessageComposerView.Coordinator.map(.cancelled) == .cancelled)
        #expect(MessageComposerView.Coordinator.map(.failed) == .failed)
    }
}
