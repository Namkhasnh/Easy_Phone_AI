import Foundation

/// `/v1/gmail/accounts` (API_GMAIL.md §3) = backend `schemas/gmail.py`. Unknown keys are ignored (API_CONTRACT §0.2).
/// The app never holds a Google token: it sends the one-time `code` + PKCE verifier only (D-151, D-310).
struct GmailConnectRequest: Codable, Sendable, Hashable {
    var schemaVersion = 1
    let code: String
    let codeVerifier: String
    let redirectUri: String
}

struct GmailAccount: Codable, Sendable, Hashable, Identifiable {
    let accountId: String
    let email: String
    let status: GmailAccountStatus

    var id: String { accountId }
}

/// `connected` / `needsReconnect` (S15 "Kết nối lại Gmail", spec §6.12 AC5). Unknown value → `.needsReconnect`.
enum GmailAccountStatus: String, Codable, Sendable, Hashable {
    case connected, needsReconnect

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GmailAccountStatus(rawValue: raw) ?? .needsReconnect
    }
}

struct GmailAccountResponse: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let account: GmailAccount
}

struct GmailAccountsResponse: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let accounts: [GmailAccount]
}

/// `POST /v1/gmail/summary` (API_GMAIL §4, 1 unit; empty inbox = 0). Read-only: mail stays unread (D-310).
struct GmailSummaryRequest: Codable, Sendable, Hashable {
    var schemaVersion = 1
    let accountId: String
    let window: Window
    let maxMessages: Int
    /// false = Gmail list + codes only (no AI, 0 units): the fast first screen, then `true` fills the summaries.
    var summarize = true
    let now: String           // ISO 8601 with offset (D-058), `ParseRequest.nowString`
    let timezone: String
    let locale: String

    enum Window: String, Codable, Sendable, Hashable { case unread, today }
}

struct GmailSummaryResponse: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let requestId: String
    let accountEmail: String
    /// May be larger than `messages.count` ("Và {count} thư khác", S21).
    let totalFound: Int
    let overview: String
    /// Oldest first; each `summary` belongs to its `messageId` (D-154).
    let messages: [GmailMessageSummary]
}

struct GmailMessageSummary: Codable, Sendable, Hashable, Identifiable {
    let messageId: String
    let threadId: String
    let fromName: String
    let subject: String
    let receivedAt: Date
    let summary: String
    let needsReply: Bool
    /// D-311: a sign-in code found by a fixed backend rule (recent mail only). Shown + copied, **never read aloud**.
    var verificationCode: String? = nil

    var id: String { messageId }
}

/// `POST /v1/gmail/drafts` (API_GMAIL §5, 0 units): saved to Gmail Drafts, **never sent** (D-103, D-304).
/// `to` is 🔒 on device until "Xác nhận", then sent once (D-307). `replyTo` is written as `null` when absent.
struct GmailDraftRequest: Codable, Sendable, Hashable {
    var schemaVersion = 1
    let accountId: String
    let to: [String]
    let subject: String
    let body: String
    var replyTo: ReplyTo?

    struct ReplyTo: Codable, Sendable, Hashable {
        let threadId: String
        let messageId: String
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, accountId, to, subject, body, replyTo }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(to, forKey: .to)
        try c.encode(subject, forKey: .subject)
        try c.encode(body, forKey: .body)
        try c.encode(replyTo, forKey: .replyTo)               // null, not missing (same bytes as the fixture)
    }
}

struct GmailDraftResponse: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let draftId: String
    let messageId: String
    let openUrl: String
}
