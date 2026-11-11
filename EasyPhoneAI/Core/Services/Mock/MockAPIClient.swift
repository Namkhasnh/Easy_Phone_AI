import Foundation
import Synchronization

/// In-memory `APIClientProtocol` for previews and tests (D-206). Never touches the network.
/// The `.mock` values are kept in code so previews need no fixture files in the app bundle (owner, 0.18 option A);
/// `ContractFixtureTests.mocksEqualFixtures` keeps them equal to `backend/tests/fixtures/contract/` (API_CONTRACT §11).
final class MockAPIClient: APIClientProtocol {
    private let meResult: Result<MeResponse, AppError>
    private let parseResult: Result<ParsedDraft, AppError>
    private let parseLog = Mutex<[(request: ParseRequest, key: IdempotencyKey)]>([])
    /// Answers for the next `parse` calls, in order; when empty, `parseResult` is returned.
    private let parseQueue: Mutex<[Result<ParsedDraft, AppError>]>
    private let transcribeResult: Result<TranscribeResponse, AppError>
    /// Answer chosen from the request (UI tests type different requests); nil → queue / `parseResult`.
    private let parseRouter: (@Sendable (ParseRequest) -> ParsedDraft?)?
    private let transcribeLog = Mutex<[Data]>([])
    private let quota = Broadcast<Quota>()
    private let blocking = Broadcast<BlockingScreen>()

    init(me: Result<MeResponse, AppError> = .success(.mock),
         parse: Result<ParsedDraft, AppError> = .success(.mockSMS),
         parseSequence: [Result<ParsedDraft, AppError>] = [],
         transcribe: Result<TranscribeResponse, AppError> = .success(.mock),
         parseRouter: (@Sendable (ParseRequest) -> ParsedDraft?)? = nil) {
        self.parseRouter = parseRouter
        meResult = me
        parseResult = parse
        parseQueue = Mutex(parseSequence)
        transcribeResult = transcribe
    }

    /// Audio of every `transcribe` call so far.
    var transcribeCalls: [Data] { transcribeLog.withLock { $0 } }

    /// Every `parse` call so far (tests check the request and that a retry reused the key).
    var parseCalls: [(request: ParseRequest, key: IdempotencyKey)] { parseLog.withLock { $0 } }

    var quotaUpdates: AsyncStream<Quota> { quota.stream }
    var blockingUpdates: AsyncStream<BlockingScreen> { blocking.stream }

    func health() async throws -> HealthResponse { .mock }

    func me() async throws -> MeResponse { try meResult.get() }

    func parse(_ request: ParseRequest, idempotencyKey: IdempotencyKey) async throws -> ParsedDraft {
        parseLog.withLock { $0.append((request, idempotencyKey)) }
        if let routed = parseRouter?(request) { return routed }
        let next = parseQueue.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        return try (next ?? parseResult).get()
    }

    func transcribe(m4a: Data, meta: MediaMeta) async throws -> TranscribeResponse {
        transcribeLog.withLock { $0.append(m4a) }
        return try transcribeResult.get()
    }
}

/// = `transcribe.ok.response.json`.
extension TranscribeResponse {
    static let mock = TranscribeResponse(schemaVersion: 1, requestId: "req_01JC8Z9E33",
                                         text: "nhắn anh minh là chiều nay em đến muộn", confidence: 0.82)
}

/// = `parse.sms.response.json` (API_CONTRACT §7.1 example A).
extension ParsedDraft {
    static let mockSMS = ParsedDraft(
        schemaVersion: 1,
        requestId: "req_01JC8Z4K3M",
        steps: [ParsedStep(kind: "sms", operation: "open", fields: [
            ParsedField(id: "recipientName", value: "anh Minh", confidence: 0.95, sourceQuote: "anh Minh"),
            ParsedField(id: "body", value: "Chiều nay em đến muộn nhé.", confidence: 0.85, sourceQuote: nil),
            ParsedField(id: "channel", value: "sms", confidence: 0.6, sourceQuote: nil),
        ], dateCandidates: [])],
        followUpQuestion: nil,
        unsupported: nil
    )
}

/// = `health.ok.response.json`.
extension HealthResponse {
    static let mock = HealthResponse(status: "ok", version: "0.1.0", schemaVersion: 1)
}

/// = `me.free.response.json`.
extension MeResponse {
    static let mock = MeResponse(
        schemaVersion: 1,
        userId: MockAuthService.userId,
        locale: "vi",
        plan: .free,
        quota: Quota(limit: 10, used: 3, remaining: 7, resetsAt: Date(timeIntervalSince1970: 1_794_157_200)), // 2026-11-09T00:00:00+07:00
        subscription: nil
    )
}
