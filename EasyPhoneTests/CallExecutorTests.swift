import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.10 — spec §6.7 AC1–AC2, D-102 (tel:// is never succeeded), D-242, D-253, DATA_MODEL §3.5.
@MainActor
@Suite("CallExecutor")
struct CallExecutorTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    let repo = MockTaskRepository()

    func draft(_ values: [String: String]) -> TaskDraft {
        let fields = FieldCatalog.mvp.fields(.call, .open).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "x", steps: [TaskStep(order: 0, kind: .call, operation: .open, fields: fields)])
        repo.save(d)
        return d
    }

    func run(_ d: TaskDraft, _ calls: MockCallService) async -> ConfirmResult {
        let e = TaskEngine(repository: repo, executors: [.call: CallExecutor(calls: calls)], now: { Self.now })
        e.revalidate(stepId: d.steps[0].id, in: d)
        return await e.confirm(stepId: d.steps[0].id, in: d)
    }

    @Test func contactNumberIsHandedOffNeverSucceeded() async {
        let calls = MockCallService()
        let d = draft(["recipientName": "mẹ", "contactId": "lan", "phoneNumber": "+84903333444"])
        #expect(await run(d, calls) == .finished(.handedOff))
        #expect(calls.calls == ["+84903333444"])
        let step = d.steps[0]
        #expect(step.state == .handedOff && step.resultEvidence == nil)          // D-102, §3.5: no evidence
        #expect(step.handoffNote == "Cần hoàn tất cuộc gọi")
        #expect(step.handoffPromptShown == false)                                // S08 asks once (D-242)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: TaskEngine(repository: repo), permissions: MockPermissionManager())
        #expect(vm.resultCard?.message == "Cần hoàn tất cuộc gọi trong ứng dụng Điện thoại.")
        #expect(vm.resultCard?.primary?.action == .markDone)                    // "Tôi đã làm xong" only by the user
    }

    @Test func spokenNumberNeedsNoContact() async {                            // D-253
        let calls = MockCallService()
        let d = draft(["recipientName": "0901 234 567", "phoneNumber": "+84901234567"])
        #expect(await run(d, calls) == .finished(.handedOff))
        #expect(calls.calls == ["+84901234567"])
    }

    // MARK: - D-300 FaceTime

    @Test func callTypeDefaultsToPhone() {
        let spec = FieldCatalog.mvp.fields(.call, .open).first { $0.id == "callType" }!
        #expect(DraftBuilder.defaultValue(spec, kind: .call, operation: .open) == "phone")
        #expect(CallType.phone.url("+84903333444") == URL(string: "tel://+84903333444"))
        #expect(CallType.facetimeAudio.url("+84903333444") == URL(string: "facetime-audio://+84903333444"))
        #expect(CallType.facetimeVideo.url("+84903333444") == URL(string: "facetime://+84903333444"))
    }

    @Test(arguments: [("facetimeAudio", CallType.facetimeAudio), ("facetimeVideo", CallType.facetimeVideo)])
    func faceTimeOpensFaceTimeAndIsHandedOff(raw: String, type: CallType) async {
        let calls = MockCallService()
        let d = draft(["recipientName": "bôm", "contactId": "b", "phoneNumber": "+84347676916", "callType": raw])
        #expect(await run(d, calls) == .finished(.handedOff))                   // never succeeded (D-102)
        #expect(calls.calls == ["+84347676916"] && calls.types == [type])
        #expect(d.steps[0].handoffNote == "Cần hoàn tất cuộc gọi FaceTime")
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: TaskEngine(repository: repo), permissions: MockPermissionManager())
        #expect(vm.resultCard?.message == "Cần hoàn tất cuộc gọi trong FaceTime.")
    }

    @Test func unknownCallTypeIsAPhoneCall() async {
        let calls = MockCallService()
        let d = draft(["recipientName": "mẹ", "contactId": "lan", "phoneNumber": "+84903333444"])
        _ = await run(d, calls)
        #expect(calls.types == [.phone])
    }

    @Test func cannotOpenFails() async {
        let calls = MockCallService(fails: true)
        let d = draft(["recipientName": "mẹ", "contactId": "lan", "phoneNumber": "+84903333444"])
        #expect(await run(d, calls) == .finished(.failed))
        #expect(d.steps[0].errorCode == "call.cannotOpen" && d.steps[0].resultEvidence == nil)
    }
}
