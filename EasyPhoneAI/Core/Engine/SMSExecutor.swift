import Foundation

/// sms/open with `channel = sms` (spec §6.8, ARCHITECTURE §5.3): asks the ViewModel to show the prefilled system
/// composer (`.needsUI`); the result comes back through `TaskEngine.composerFinished` (`.sent` → `msg:sent:<date>`).
/// Never sends by itself (D-103). Other channels (copy + open app, D-162 / D-247) are 1C.12.
@MainActor final class SMSExecutor: StepExecutor {
    private let messages: any MessagesService

    nonisolated init(messages: any MessagesService) { self.messages = messages }

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        guard (step.field("channel")?.value ?? "sms") == "sms" else {
            // TODO(spec): the copy-guide path for other channels comes with 1C.12 (S07).
            return .failed(code: "unsupported")
        }
        guard messages.canSendText else { return .failed(code: "messages.cannotSend") }   // UI: error.messages.cannotSend
        guard let raw = step.field("phoneNumber")?.value, let number = PhoneNumber.normalize(raw) else {
            return .failed(code: "messages.cannotSend")
        }
        return .needsUI(.composer(recipients: [number], body: step.field("body")?.value ?? ""))
    }
}
