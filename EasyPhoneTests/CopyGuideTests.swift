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

    @Test func bundledFileZaloVerifiedOthersNot() throws {
        let services = SupportedServices.bundled
        #expect(services.schemaVersion == 1)
        #expect(services.ids == ["zalo", "grab"])
        let zalo = try #require(services.service("zalo"))
        #expect(zalo.name == "Zalo" && zalo.kinds == ["sms"] && zalo.guideSteps.count == 4)
        #expect(zalo.verified && zalo.openURL == URL(string: "zalo://"))       // D-297 locks D-161 for Zalo
        #expect(zalo.chatURL(for: "+84903333444") == URL(string: "https://zalo.me/84903333444"))
        #expect(services.service("grab")?.verified == false)                   // D-162 for the rest
        #expect(services.service("sms") == nil)                                 // built in, not listed (D-247)
    }

    static let copyOnly = SupportedServices(schemaVersion: 1, services: [
        .init(id: "viber", name: "Viber", kinds: ["sms"], urlScheme: "viber://", verified: false,
              guideSteps: ["Mở Viber", "Chọn người nhận", "Dán tin nhắn", "Bấm Gửi"])])

    static let mom = ["recipientName": "mẹ", "body": "Chiều nay con về muộn nhé mẹ.", "contactId": "lan",
                      "phoneNumber": "+84903333444"]

    func review(_ services: SupportedServices = .bundled, channel: String = "zalo",
                values: [String: String] = mom) -> ReviewViewModel {
        let e = TaskEngine(repository: repo,
                           executors: [.sms: SMSExecutor(messages: MockMessagesService(), system: system, services: services)],
                           serviceIds: services.ids, now: { Self.now })
        var values = values
        values["channel"] = channel
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

    @Test func zaloOpensThePersonsChat() async throws {                      // D-297
        let vm = review()
        #expect(vm.blocker == nil)
        await vm.confirm()
        #expect(system.copied == ["Chiều nay con về muộn nhé mẹ."])
        #expect(system.opened == [URL(string: "https://zalo.me/84903333444")!])
        let step = try #require(vm.step)
        #expect(step.state == .handedOff && step.resultEvidence == nil)         // never succeeded (D-102)
        #expect(step.handoffNote == "Đã sao chép — dán vào khung chat Zalo rồi bấm Gửi")
        #expect(vm.copyGuide == nil)                                            // the chat is open, no guide needed
    }

    @Test func zaloWithoutContactCannotConfirm() {                           // D-297: number required again
        let vm = review(values: ["recipientName": "mẹ", "body": "Chiều nay con về muộn nhé mẹ."])
        #expect(vm.blocker == .missing)
    }

    @Test func chatLinkFailsFallsBackToTheGuide() async throws {
        let failing = MockSystemService(canOpen: false)
        let e = TaskEngine(repository: repo,
                           executors: [.sms: SMSExecutor(messages: MockMessagesService(), system: failing)],
                           serviceIds: SupportedServices.bundled.ids, now: { Self.now })
        let fields = FieldCatalog.mvp.fields(.sms, .open).map {
            Field(id: $0.id, type: $0.type, value: (Self.mom.merging(["channel": "zalo"]) { $1 })[$0.id], source: .ai,
                  deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "x", steps: [TaskStep(order: 0, kind: .sms, operation: .open, fields: fields)])
        repo.save(d)
        e.revalidate(stepId: d.steps[0].id, in: d)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: MockPermissionManager(),
                                 system: failing)
        await vm.confirm()
        #expect(vm.step?.handoffNote == "Đã sao chép — dán và gửi trong Zalo")
        #expect(vm.copyGuide?.serviceName == "Zalo")
    }

    @Test func unverifiedServiceCopiesHandsOffAndShowsTheGuide() async throws {   // D-162, D-247
        let vm = review(Self.copyOnly, channel: "viber", values: ["recipientName": "mẹ", "body": "Chiều nay con về muộn nhé mẹ."])
        #expect(vm.blocker == nil)                                             // no contact needed
        await vm.confirm()
        #expect(system.copied == ["Chiều nay con về muộn nhé mẹ."])
        #expect(system.opened.isEmpty)                                          // unverified → not opened
        let step = try #require(vm.step)
        #expect(step.state == .handedOff && step.handoffNote == "Đã sao chép — dán và gửi trong Viber")
        let guide = try #require(vm.copyGuide)
        #expect(guide.serviceName == "Viber" && guide.steps.count == 4)
        await vm.copyAgain()
        #expect(system.copied.count == 2)
        vm.copyGuideDone()                                                      // user says it was sent (D-242)
        #expect(vm.copyGuide == nil && vm.step?.state == .userMarkedDone)
    }

    @Test func copyStringsExist() {
        #expect(UserMessage(key: "copy.title", args: ["Zalo"]).text == "Gửi qua Zalo")
        for key in ["copy.stepsTitle", "copy.again", "common.yesDone"] { #expect(UserMessage(key: key).text != key) }
    }
}
