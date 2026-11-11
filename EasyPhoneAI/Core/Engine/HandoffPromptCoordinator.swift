import Foundation
import Observation
import OSLog

/// What S08 shows for one hand-off (UI_SCREENS S08, D-242).
struct HandoffPrompt: Identifiable, Hashable, Sendable {
    let draftId: UUID
    let stepId: UUID
    let symbol: String
    let question: UserMessage        // `handoff.call` / `handoff.directions` / `handoff.copyMessage`
    let summary: String              // step summary (`history.summary`)
    var id: UUID { stepId }
}

/// ARCHITECTURE §5.4, D-242: when the app is active again after a hand-off, asks **once** "Bạn đã … xong chưa?".
/// "Đã xong" → `userMarkedDone`; "Chưa" → stays `handedOff` (History "Việc chưa xong") + toast. Never auto-completes.
@Observable @MainActor final class HandoffPromptCoordinator {
    private(set) var prompt: HandoffPrompt?
    var toast: UserMessage?

    private let repository: any TaskRepository
    private let engine: TaskEngine
    private let services: SupportedServices
    /// True on launch (a cold start after a hand-off asks too) and after every `.background`.
    private var returning = true
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "handoff")

    init(repository: any TaskRepository, engine: TaskEngine, services: SupportedServices = .bundled) {
        self.repository = repository
        self.engine = engine
        self.services = services
    }

    func didEnterBackground() { returning = true }

    /// `scenePhase == .active`. Only after a real return from another app: the system "Gọi …?" alert of `tel://`
    /// makes the app `.inactive` → `.active` without leaving it, which must not ask yet.
    // TODO(spec): ARCHITECTURE §5.4 says "on `.active`"; `.inactive` → `.active` (system alerts) is ignored here.
    func didBecomeActive() {
        guard returning, prompt == nil else { return }
        returning = false
        let pending = repository.steps(in: [.handedOff]).filter { !$0.1.handoffPromptShown }
        guard let (draftId, step) = pending.max(by: { $0.1.stateChangedAt < $1.1.stateChangedAt }) else { return }
        guard let question = question(for: step) else {
            logger.warning("no S08 question for \(step.kind.rawValue, privacy: .public)")
            return
        }
        prompt = HandoffPrompt(draftId: draftId, stepId: step.id, symbol: DraftRowBuilder.symbol(step.kind),
                               question: question, summary: DraftRowBuilder.summary(step))
    }

    /// The sheet is on screen: this hand-off is never asked again (D-242). Called from the sheet's `onAppear`, so a
    /// prompt SwiftUI could not present (another sheet open) is asked on the next return.
    func didShow() {
        guard let prompt, let draft = repository.draft(prompt.draftId) else { return }
        engine.markHandoffPromptShown(stepId: prompt.stepId, in: draft)
    }

    /// "Đã xong" (`common.yesDone`) → `userMarkedDone`.
    func answerDone() {
        guard let prompt else { return }
        if let draft = repository.draft(prompt.draftId) { engine.markDone(stepId: prompt.stepId, in: draft) }
        self.prompt = nil
    }

    /// "Chưa" (`common.notYet`) → stays `handedOff`, toast `handoff.notYet.toast`.
    func answerNotYet() {
        guard prompt != nil else { return }
        prompt = nil
        toast = UserMessage(key: "handoff.notYet.toast")
    }

    /// Swipe-down without an answer: same as "Chưa", without the toast.
    // TODO(spec): UI_SCREENS S08 does not say what a swipe-down means; treated as "Chưa" (stays handedOff).
    func dismissed() { prompt = nil }

    // TODO(spec): ride / food keys come with Phase 3 (D-150); voice "có" = "Đã xong" waits for S08 voice mode.
    private func question(for step: TaskStep) -> UserMessage? {
        switch step.kind {
        case .call: return UserMessage(key: "handoff.call")
        case .place: return UserMessage(key: "handoff.directions")
        case .sms:
            let channel = step.field("channel")?.value ?? "sms"
            let name = services.service(channel)?.name ?? channel
            return UserMessage(key: "handoff.copyMessage", args: [name])
        default: return nil
        }
    }
}
