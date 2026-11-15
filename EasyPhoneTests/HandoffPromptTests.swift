import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.15 — D-242, ARCHITECTURE §5.4, UI_SCREENS S08: one return prompt per hand-off, never auto-complete.
@MainActor
@Suite("Hand-off return prompt (S08, D-242)")
struct HandoffPromptTests {
    let repo = MockTaskRepository()
    let engine: TaskEngine
    let coordinator: HandoffPromptCoordinator

    init() {
        engine = TaskEngine(repository: repo)
        coordinator = HandoffPromptCoordinator(repository: repo, engine: engine)
    }

    @discardableResult
    func handedOff(_ kind: TaskKind, operation: TaskOperation = .open, values: [String: String] = [:],
                   at: Date = .now, shown: Bool = false) -> TaskDraft {
        let fields = values.map { Field(id: $0.key, type: .text, value: $0.value, source: .ai) }
        let step = TaskStep(order: 0, kind: kind, operation: operation, state: .handedOff, fields: fields,
                            handoffPromptShown: shown, stateChangedAt: at)
        let d = TaskDraft(inputMode: .text, originalInput: "", steps: [step])
        repo.save(d)
        return d
    }

    @Test func callAsksOnceAndDoneMarksDone() {
        let d = handedOff(.call, values: ["recipientName": "anh Minh"])
        coordinator.didBecomeActive()
        let prompt = try! #require(coordinator.prompt)
        #expect(prompt.question == UserMessage(key: "handoff.call"))
        #expect(prompt.summary.contains("anh Minh"))
        #expect(prompt.stepId == d.steps[0].id)

        coordinator.didShow()
        #expect(d.steps[0].handoffPromptShown)
        coordinator.answerDone()
        #expect(d.steps[0].state == .userMarkedDone)
        #expect(coordinator.prompt == nil)
    }

    @Test func notYetStaysHandedOffShowsToastAndIsNotAskedAgain() {
        let d = handedOff(.place, values: ["name": "Nhà"])
        coordinator.didBecomeActive()
        #expect(coordinator.prompt?.question == UserMessage(key: "handoff.directions"))
        coordinator.didShow()
        coordinator.answerNotYet()
        #expect(d.steps[0].state == .handedOff)
        #expect(coordinator.toast == UserMessage(key: "handoff.notYet.toast"))

        coordinator.didEnterBackground()
        coordinator.didBecomeActive()
        #expect(coordinator.prompt == nil)
    }

    @Test func copyMessageNamesTheService() {
        handedOff(.sms, operation: .create, values: ["channel": "zalo", "recipientName": "chị Lan"])
        coordinator.didBecomeActive()
        #expect(coordinator.prompt?.question == UserMessage(key: "handoff.copyMessage", args: ["Zalo"]))
    }

    @Test func newestUnaskedHandoffWins() {
        handedOff(.call, at: Date(timeIntervalSince1970: 100))
        handedOff(.call, at: Date(timeIntervalSince1970: 50), shown: false)
        let newest = handedOff(.place, at: Date(timeIntervalSince1970: 200))
        handedOff(.call, at: Date(timeIntervalSince1970: 300), shown: true)
        coordinator.didBecomeActive()
        #expect(coordinator.prompt?.draftId == newest.id)
    }

    @Test func inactiveToActiveWithoutBackgroundDoesNotAsk() {
        coordinator.didBecomeActive()                       // launch, nothing pending
        handedOff(.call)                                    // tel:// alert: .inactive → .active, app never left
        coordinator.didBecomeActive()
        #expect(coordinator.prompt == nil)
        coordinator.didEnterBackground()
        coordinator.didBecomeActive()
        #expect(coordinator.prompt != nil)
    }

    @Test func promptNotPresentedIsAskedOnNextReturn() {
        let d = handedOff(.call)
        coordinator.didBecomeActive()
        coordinator.dismissed()                             // never appeared (another sheet), didShow not called
        #expect(!d.steps[0].handoffPromptShown)
        coordinator.didEnterBackground()
        coordinator.didBecomeActive()
        #expect(coordinator.prompt?.stepId == d.steps[0].id)
    }

    @Test func enteringHandedOffResetsTheShownFlag() {
        var step = TaskStep(order: 0, kind: .call, operation: .open, state: .processing, handoffPromptShown: true)
        let d = TaskDraft(inputMode: .text, originalInput: "", steps: [step])
        repo.save(d)
        #expect(engine.apply(.outcomeUnknownHandoff, stepId: d.steps[0].id, in: d))
        step = d.steps[0]
        #expect(step.state == .handedOff)
        #expect(!step.handoffPromptShown)
    }
}
