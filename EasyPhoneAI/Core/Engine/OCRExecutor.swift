import Foundation

/// `ocr.create` (DATA_MODEL §3.5): confirming the photo's information is local, evidence `local:confirmed`.
/// `nextAction = copyContactInfo` copies the name + phone number to the clipboard (D-226: no Contacts write in MVP).
/// The linked calendarEvent / reminder step is appended by `TaskEngine` after success (DATA_MODEL §4, D-120).
@MainActor struct OCRExecutor: StepExecutor {
    static let evidence = "local:confirmed"

    let system: any SystemService

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        if step.field("nextAction")?.value == "copyContactInfo", let text = Self.contactText(step) {
            await system.copy(text)
        }
        return .verified(evidence: Self.evidence)
    }

    /// Local only: nothing to find again after a kill, the confirmation itself is the evidence.
    func evidenceOnLaunch(_ step: TaskStep) async -> String? { Self.evidence }

    /// Name and phone, one per line; empty ones skipped; nil when both are empty.
    // TODO(spec): DATA_MODEL §4 / D-226 do not give the copied text's format; "name\nphone" is used.
    static func contactText(_ step: TaskStep) -> String? {
        let parts = ["personName", "phoneNumber"].compactMap { id -> String? in
            guard let value = step.field(id)?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
