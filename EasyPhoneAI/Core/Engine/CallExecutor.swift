import Foundation

/// call/open (spec §6.7, ARCHITECTURE §5.1): opens `tel://` and hands off — never `succeeded`, never evidence (D-102,
/// DATA_MODEL §3.5). The S08 return prompt asks once whether the call was done (D-242, 1C.15).
@MainActor final class CallExecutor: StepExecutor {
    private let calls: any CallService

    nonisolated init(calls: any CallService) { self.calls = calls }

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        // `phoneNumber` is E.164 (D-253 / DeviceResolver); anything else is normalized once more for safety.
        guard let raw = step.field("phoneNumber")?.value, let number = PhoneNumber.normalize(raw) else {
            // TODO(spec): no error key for a missing / invalid number at execute time (Validator blocks it before).
            return .failed(code: "call.cannotOpen")
        }
        let type = CallType(rawValue: step.field("callType")?.value ?? "") ?? .phone      // D-300
        do {
            try await calls.start(e164: number, type: type)
            return .handedOff(note: UserMessage(key: type == .phone ? "handoff.note.call" : "handoff.note.facetime").text)
        } catch let error as ServiceError {
            return .failed(code: error.code)
        } catch {
            return .failed(code: "call.cannotOpen")
        }
    }
}
