import Foundation

/// `emailReply.create` (API_GMAIL §5, D-304, D-307): after "Xác nhận" the email is saved to the user's Gmail
/// Drafts through the backend. **Never sent** (D-103). Gmail returns the draft id = evidence
/// `gmail:draft:<draftId>` → `succeeded` (D-124). Key = the step id, so "Thử lại" after a lost answer returns the
/// same draft instead of a second one (D-105).
@MainActor struct EmailDraftExecutor: StepExecutor {
    static let evidencePrefix = "gmail:draft:"

    let api: any APIClientProtocol
    let gmail: any GmailService

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        guard let to = step.field("toAddress")?.value, DeviceResolver.isEmailAddress(to),
              let body = step.field("body")?.value, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failed(code: "invalid_input") }
        let account: GmailAccount
        do {
            guard let first = try await gmail.accounts().first else { return .failed(code: "gmail_not_connected") }
            account = first
        } catch {
            return .failed(code: Self.code(error))
        }
        guard account.status == .connected else { return .failed(code: "gmail_reconnect_required") }
        var request = GmailDraftRequest(accountId: account.accountId, to: [to],
                                        subject: step.field("subject")?.value ?? "", body: body)
        if let thread = step.field("threadId")?.value, let message = step.field("messageId")?.value {
            request.replyTo = .init(threadId: thread, messageId: message)
        }
        do {
            let created = try await api.gmailDraft(request, idempotencyKey: IdempotencyKey(step: step.id))
            return .verified(evidence: Self.evidencePrefix + created.draftId)
        } catch {
            return .failed(code: Self.code(error))
        }
    }

    // Launch verification (D-125): re-sending with the same key would create the draft if it was never made, which
    // is not read-only; the step stays `unknown` and the user retries (same key → no duplicate).

    static func code(_ error: any Error) -> String {
        (error as? AppError)?.code ?? (error as? ServiceError)?.code ?? "internal"
    }
}
