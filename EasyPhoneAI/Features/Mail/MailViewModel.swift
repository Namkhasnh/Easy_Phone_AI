import Foundation
import Observation

/// S21 Mail summary (UI_SCREENS S21, API_GMAIL §4, D-304, D-308, D-310). Opened from "có thư mới không"
/// (`checkMail`). Nothing is stored on the phone; the summary lives in memory only. Mail stays unread in Gmail.
@Observable @MainActor final class MailViewModel {
    enum Phase: Equatable {
        case loading
        /// No Gmail connected → EmptyState + Primary "Kết nối Gmail".
        case notConnected
        /// Token dead (7-day Testing expiry, revoked) → EmptyState + Primary "Kết nối lại Gmail".
        case needsReconnect
        case loaded(GmailSummaryResponse)
        case failed(UserMessage)
    }

    private(set) var phase: Phase = .loading
    /// Id of the row being read aloud (`overviewId` for the overview card), nil when silent.
    private(set) var readingId: String?
    static let overviewId = "overview"
    /// The message whose code was just copied ("Đã sao chép mã").
    private(set) var copiedCodeId: String?
    /// D-311: the clipboard forgets the code after this many seconds.
    static let codeClipboardSeconds: TimeInterval = 120

    private let gmail: any GmailService
    private let api: any APIClientProtocol
    private let tts: any TTSService
    private let system: any SystemService
    private let speechRate: Double
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    init(gmail: any GmailService, api: any APIClientProtocol, tts: any TTSService = MockTTSService(),
         system: any SystemService = MockSystemService(),
         speechRate: Double = 0.45, now: @escaping @Sendable () -> Date = { .now }, timeZone: TimeZone = .current) {
        self.system = system
        self.gmail = gmail
        self.api = api
        self.tts = tts
        self.speechRate = speechRate
        self.now = now
        self.timeZone = timeZone
    }

    /// Accounts → summary (1 unit; an empty inbox costs nothing, D-308). "Tải lại" calls it again with a new key.
    func load() async {
        stopReading()
        phase = .loading
        do {
            guard let account = try await gmail.accounts().first else { phase = .notConnected; return }
            guard account.status == .connected else { phase = .needsReconnect; return }
            let request = GmailSummaryRequest(accountId: account.accountId, window: .unread,
                                              maxMessages: Self.maxMessages, now: ParseRequest.nowString(now(), in: timeZone),
                                              timezone: timeZone.identifier, locale: "vi-VN")
            phase = .loaded(try await api.gmailSummary(request, idempotencyKey: IdempotencyKey()))
        } catch is CancellationError {
        } catch {
            phase = Self.phase(for: error)
        }
    }

    // TODO(spec): API_GMAIL §4 gives `maxMessages` 1–10 and no app default; the app asks for the maximum.
    static let maxMessages = 10

    /// "Kết nối Gmail" / "Kết nối lại Gmail" from the empty state, then the summary.
    func connect() async {
        do {
            _ = try await gmail.connect()
            await load()
        } catch is CancellationError {
        } catch {
            phase = .failed(SettingsViewModel.gmailFailure(error))
        }
    }

    static func phase(for error: any Error) -> Phase {
        guard let error = error as? AppError else { return .failed(UserMessage(key: "error.generic")) }
        switch error.code {
        case "gmail_not_connected": return .notConnected
        case "gmail_reconnect_required": return .needsReconnect
        default: return .failed(UserMessage(key: ConversationViewModel.noticeKey(forParseError: error.code)))
        }
    }

    // MARK: - Read aloud (spec §6.2 AC5: tap again stops)

    func toggleReading(_ id: String, text: String) async {
        if readingId == id { stopReading(); return }
        stopReading()
        readingId = id
        await tts.speak(text, rate: speechRate)
        if readingId == id { readingId = nil }
    }

    func stopReading() {
        guard readingId != nil else { return }
        tts.stop()
        readingId = nil
    }

    /// What one row reads aloud: sender, subject, summary — with any verification code taken out (D-311: never
    /// read aloud) and a hint to look at the screen instead.
    static func spoken(_ message: GmailMessageSummary) -> String {
        let parts = [message.fromName, message.subject, message.summary].filter { !$0.isEmpty }
        guard let code = message.verificationCode else { return parts.joined(separator: ". ") }
        let clean = parts.map { $0.replacingOccurrences(of: code, with: "") }
        return (clean + [UserMessage(key: "mail.code.spoken").text]).joined(separator: ". ")
    }

    /// The overview read aloud, without any code of the loaded messages (D-311).
    static func spokenOverview(_ response: GmailSummaryResponse) -> String {
        response.messages.compactMap(\.verificationCode)
            .reduce(response.overview) { $0.replacingOccurrences(of: $1, with: "") }
    }

    /// Messages with a code, newest first (the newest is usually the one the user waits for).
    static func codes(_ response: GmailSummaryResponse) -> [GmailMessageSummary] {
        response.messages.filter { $0.verificationCode != nil }.sorted { $0.receivedAt > $1.receivedAt }
    }

    /// "Sao chép mã": device-only clipboard that clears itself (D-311).
    func copyCode(_ message: GmailMessageSummary) async {
        guard let code = message.verificationCode else { return }
        await system.copySecret(code, expiresAfter: Self.codeClipboardSeconds)
        copiedCodeId = message.messageId
    }

    /// "Và {count} thư khác" when Gmail found more than it returned.
    static func moreCount(_ response: GmailSummaryResponse) -> Int? {
        let extra = response.totalFound - response.messages.count
        return extra > 0 ? extra : nil
    }
}
