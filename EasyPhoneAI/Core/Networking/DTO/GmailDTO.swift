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

    var id: String { messageId }
}
