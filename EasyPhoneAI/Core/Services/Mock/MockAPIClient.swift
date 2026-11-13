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
    private let ocrResult: Result<OCRResponse, AppError>
    private let ocrLog = Mutex<[(jpeg: Data, key: IdempotencyKey)]>([])
    private let extractResult: Result<ExtractResponse, AppError>
    private let extractLog = Mutex<[(request: ExtractRequest, key: IdempotencyKey)]>([])
    private let quota = Broadcast<Quota>()
    private let blocking = Broadcast<BlockingScreen>()

    init(me: Result<MeResponse, AppError> = .success(.mock),
         parse: Result<ParsedDraft, AppError> = .success(.mockSMS),
         parseSequence: [Result<ParsedDraft, AppError>] = [],
         transcribe: Result<TranscribeResponse, AppError> = .success(.mock),
         parseRouter: (@Sendable (ParseRequest) -> ParsedDraft?)? = nil,
         ocr: Result<OCRResponse, AppError> = .success(.mock),
         extract: Result<ExtractResponse, AppError> = .success(.mock)) {
        self.parseRouter = parseRouter
        ocrResult = ocr
        extractResult = extract
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

    /// Every `ocr` call so far (tests check the key and that the saved JPEG was sent).
    var ocrCalls: [(jpeg: Data, key: IdempotencyKey)] { ocrLog.withLock { $0 } }

    func ocr(jpeg: Data, meta: MediaMeta, idempotencyKey: IdempotencyKey) async throws -> OCRResponse {
        ocrLog.withLock { $0.append((jpeg, idempotencyKey)) }
        return try ocrResult.get()
    }

    /// Every `extract` call so far.
    var extractCalls: [(request: ExtractRequest, key: IdempotencyKey)] { extractLog.withLock { $0 } }

    func extract(_ request: ExtractRequest, idempotencyKey: IdempotencyKey) async throws -> ExtractResponse {
        extractLog.withLock { $0.append((request, idempotencyKey)) }
        return try extractResult.get()
    }
}

/// = `extract.appointment.response.json` (API_CONTRACT §7.2 example).
extension ExtractResponse {
    static let mock = ExtractResponse(schemaVersion: 1, requestId: "req_01JC8Z7C10", fields: [
        .init(id: "title", value: "Phòng khám Nha khoa An Bình", confidence: 0.8, span: .init(start: 0, end: 27)),
        .init(id: "dateTime", value: "2026-11-14T09:30:00+07:00", confidence: 0.85, span: .init(start: 38, end: 59)),
        .init(id: "address", value: "215 Hồng Bàng, Q5", confidence: 0.8, span: .init(start: 69, end: 86)),
        .init(id: "personName", value: "Trần Văn Hùng", confidence: 0.75, span: .init(start: 91, end: 104)),
        .init(id: "phoneNumber", value: "0901 234 567", confidence: 0.9, span: .init(start: 107, end: 119)),
    ], suggestedNextAction: "calendarEvent")
}

/// = `ocr.ok.response.json` (API_CONTRACT §7.3 example).
extension OCRResponse {
    static let mock = OCRResponse(schemaVersion: 1, requestId: "req_01JC8Z8D22",
                                  text: "PHÒNG KHÁM NHA KHOA AN BÌNH\nLịch hẹn: 09:30 ngày 14/11/2026",
                                  lines: [.init(text: "PHÒNG KHÁM NHA KHOA AN BÌNH", box: OCRBox(x: 0.08, y: 0.86, width: 0.84, height: 0.05)),
                                          .init(text: "Lịch hẹn: 09:30 ngày 14/11/2026", box: OCRBox(x: 0.08, y: 0.78, width: 0.70, height: 0.04))])
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
