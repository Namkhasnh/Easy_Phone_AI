import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.12 — DATA_MODEL §10 SupportedServices, UI_SCREENS S07, spec §6.8 AC3, D-102, D-162, D-242, D-247.
@MainActor
@Suite("SupportedServices + S07 copy guide")
struct CopyGuideTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    let repo = MockTaskRepository()
    let system = MockSystemService()

    @Test func bundledFileMatchesTheDocAndIsUnverified() throws {
        let services = SupportedServices.bundled
        #expect(services.schemaVersion == 1)
        #expect(services.ids == ["zalo", "grab"])
        let zalo = try #require(services.service("zalo"))
        #expect(zalo.name == "Zalo" && zalo.kinds == ["sms"] && zalo.guideSteps.count == 4)
        #expect(services.services.allSatisfy { !$0.verified })                 // D-162 until D-161 is locked
        #expect(zalo.openURL == nil)                                            // never opened while unverified
        #expect(services.service("sms") == nil)                                 // built in, not listed (D-247)
    }

    func review(_ services: SupportedServices = .bundled) -> ReviewViewModel {
        let e = TaskEngine(repository: repo,
                           executors: [.sms: SMSExecutor(messages: MockMessagesService(), system: system, services: services)],
                           serviceIds: services.ids, now: { Self.now })
        let values = ["recipientName": "mẹ", "body": "Chiều nay con về muộn nhé mẹ.", "channel": "zalo"]
        let fields = FieldCatalog.mvp.fields(.sms, .open).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "x",
                          steps: [TaskStep(order: 0, kind: .sms, operation: .open, fields: fields)])
        repo.save(d)
        e.revalidate(stepId: d.steps[0].id, in: d)
        return ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: MockPermissionManager(),
                               system: system, services: services)
    }

    @Test func zaloCopiesHandsOffAndShowsTheGuide() async throws {
        let vm = review()
        #expect(vm.blocker == nil)                                             // no contact needed (D-247)
        await vm.confirm()
        #expect(system.copied == ["Chiều nay con về muộn nhé mẹ."])
        #expect(system.opened.isEmpty)                                          // unverified → not opened (D-162)
        let step = try #require(vm.step)
        #expect(step.state == .handedOff && step.resultEvidence == nil)         // never succeeded (D-102)
        #expect(step.handoffNote == "Đã sao chép — dán và gửi trong Zalo")
        let guide = try #require(vm.copyGuide)
        #expect(guide.serviceName == "Zalo" && guide.steps == ["Mở Zalo", "Chọn người nhận", "Dán tin nhắn", "Bấm Gửi"])
        await vm.copyAgain()
        #expect(system.copied.count == 2)
        vm.copyGuideDone()                                                      // user says it was sent (D-242)
        #expect(vm.copyGuide == nil && vm.step?.state == .userMarkedDone)
    }

    @Test func verifiedServiceOpensItsApp() async {
        let verified = SupportedServices(schemaVersion: 1, services: [
            .init(id: "zalo", name: "Zalo", kinds: ["sms"], urlScheme: "zalo://", verified: true, guideSteps: [])])
        let vm = review(verified)
        await vm.confirm()
        #expect(system.opened == [URL(string: "zalo://")!])
        #expect(vm.step?.state == .handedOff)
    }

    @Test func copyStringsExist() {
        #expect(UserMessage(key: "copy.title", args: ["Zalo"]).text == "Gửi qua Zalo")
        for key in ["copy.stepsTitle", "copy.again", "common.yesDone"] { #expect(UserMessage(key: key).text != key) }
    }
}
