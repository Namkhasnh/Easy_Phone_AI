import Foundation

/// sms/open with `channel = sms` (spec §6.8, ARCHITECTURE §5.3): asks the ViewModel to show the prefilled system
/// composer (`.needsUI`); the result comes back through `TaskEngine.composerFinished` (`.sent` → `msg:sent:<date>`).
/// Never sends by itself (D-103). Other channels (Zalo…, spec §6.8 AC3): the text is copied, the app is opened only when
/// its scheme is verified (D-162), the step is `handedOff` with "Đã sao chép — dán và gửi trong {service}" and S07 guides
/// the user. No contact lookup on that path (D-247).
@MainActor final class SMSExecutor: StepExecutor {
    private let messages: any MessagesService
    private let system: any SystemService
    private let services: SupportedServices

    nonisolated init(messages: any MessagesService, system: any SystemService = MockSystemService(),
                     services: SupportedServices = .bundled) {
        self.messages = messages
        self.system = system
        self.services = services
    }

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        let channel = step.field("channel")?.value ?? "sms"
        guard channel == "sms" else { return await copyPath(step, channel: channel) }
        guard messages.canSendText else { return .failed(code: "messages.cannotSend") }   // UI: error.messages.cannotSend
        guard let raw = step.field("phoneNumber")?.value, let number = PhoneNumber.normalize(raw) else {
            return .failed(code: "messages.cannotSend")
        }
        return .needsUI(.composer(recipients: [number], body: step.field("body")?.value ?? ""))
    }

    /// S07 path: copy, open only a verified app, hand off (never `succeeded`, D-102).
    /// D-297: a verified service with `chatURL` (Zalo) opens the person's chat; the user pastes and taps Send there.
    /// If that link does not open, the app itself (when installed) + the S07 guide, as before.
    private func copyPath(_ step: TaskStep, channel: String) async -> ExecutionOutcome {
        guard let service = services.service(channel), service.kinds.contains("sms") else { return .failed(code: "unsupported") }
        await system.copy(step.field("body")?.value ?? "")
        if let raw = step.field("phoneNumber")?.value, let number = PhoneNumber.normalize(raw),
           let chat = service.chatURL(for: number), await system.open(chat) {
            return .handedOff(note: Self.chatNote(service.name))
        }
        if let url = service.openURL, await system.canOpen(url) { _ = await system.open(url) }
        return .handedOff(note: UserMessage(key: "handoff.note.copy", args: [service.name]).text)
    }

    /// Hand-off note when the person's chat was opened (no S07 guide needed then).
    static func chatNote(_ serviceName: String) -> String {
        UserMessage(key: "handoff.note.copyChat", args: [serviceName]).text
    }
}
