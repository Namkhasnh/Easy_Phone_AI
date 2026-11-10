import Foundation
import Synchronization
import Testing
@testable import EasyPhoneAI

/// Scripted transport: `handler(request, callIndex)`; records every request.
private final class StubTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest, Int) throws -> (Data, HTTPURLResponse)
    private let calls = Mutex<[URLRequest]>([])
    private let handler: Handler

    init(_ handler: @escaping Handler) { self.handler = handler }

    var requests: [URLRequest] { calls.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = calls.withLock { $0.append(request); return $0.count - 1 }
        return try handler(request, index)
    }
}

/// `t0` = current token, `t1` = after refresh.
private final class FakeAuth: AuthService {
    private let counts = Mutex((refreshes: 0, signOuts: 0))
    private let refreshFails: Bool

    init(refreshFails: Bool = false) { self.refreshFails = refreshFails }

    var refreshes: Int { counts.withLock { $0.refreshes } }
    var signOuts: Int { counts.withLock { $0.signOuts } }

    var sessionUpdates: AsyncStream<SessionState> { AsyncStream { $0.finish() } }
    func signInWithGoogle() async throws {}

    func accessToken(forceRefresh: Bool) async throws -> String {
        guard forceRefresh else { return "t0" }
        counts.withLock { $0.refreshes += 1 }
        try await Task.sleep(for: .milliseconds(50))
        if refreshFails { throw ServiceError.unavailable(AuthErrorCode.notSignedIn) }
        return "t1"
    }

    func signOut() async { counts.withLock { $0.signOuts += 1 } }
}

private func reply(_ status: Int, _ json: String, headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
    let response = HTTPURLResponse(url: URL(string: "https://api.mock.invalid")!, statusCode: status,
                                   httpVersion: "HTTP/1.1", headerFields: headers.merging(["X-Request-Id": "req_test"]) { a, _ in a })!
    return (Data(json.utf8), response)
}

private func envelope(_ code: String, retryable: Bool = false, details: String = "null") -> String {
    #"{"error":{"code":"\#(code)","message":"m","retryable":\#(retryable),"requestId":"req_env","details":\#(details)}}"#
}

private let meJSON = #"""
{"schemaVersion":1,"userId":"6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11","locale":"vi","plan":"free",
 "quota":{"limit":10,"used":3,"remaining":7,"resetsAt":"2026-11-09T00:00:00+07:00"},"subscription":null}
"""#

private let quotaHeaders = ["X-Quota-Limit": "10", "X-Quota-Remaining": "7",
                            "X-Quota-Resets-At": "2026-11-10T00:00:00+07:00"]

private final class SleepRecorder: Sendable {
    private let log = Mutex<[Duration]>([])
    var durations: [Duration] { log.withLock { $0 } }
    func record(_ duration: Duration) { log.withLock { $0.append(duration) } }
}

private func makeClient(_ transport: StubTransport, auth: FakeAuth = FakeAuth(),
                        sleeps: SleepRecorder = SleepRecorder()) -> APIClient {
    APIClient(config: .mock, auth: auth, transport: transport, client: .mock,
              retryPolicy: RetryPolicy(jitter: { 0 }),
              sleep: { sleeps.record($0) })
}

@Suite("APIClient (API_CONTRACT §1, §2, §10)")
struct APIClientTests {
    // MARK: - POST /v1/parse (1B.10b)

    static let parseOK = #"""
    {"schemaVersion":1,"requestId":"req_p","steps":[{"kind":"reminder","operation":"create","fields":[
     {"id":"title","value":"Uống thuốc","confidence":0.9,"sourceQuote":"uống thuốc"},
     {"id":"dueDate","value":null,"confidence":null,"sourceQuote":null}],"dateCandidates":[]}],
     "followUpQuestion":"Bạn muốn được nhắc lúc mấy giờ?","unsupported":null}
    """#

    static func parseRequest() -> ParseRequest {
        ParseRequest(text: "Nhắc tôi uống thuốc", inputMode: .text, now: "2026-11-08T18:07:00+07:00",
                     timezone: "Asia/Ho_Chi_Minh", locale: "vi-VN", savedPlaceLabels: ["home"], context: .none)
    }

    @Test func parsePostsJSONWithKeyAndDecodes() async throws {
        let transport = StubTransport { _, _ in reply(200, Self.parseOK, headers: quotaHeaders) }
        let key = IdempotencyKey()
        let draft = try await makeClient(transport).parse(Self.parseRequest(), idempotencyKey: key)

        #expect(draft.steps.first?.fields.last?.value == nil)
        #expect(draft.followUpQuestion == "Bạn muốn được nhắc lúc mấy giờ?")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.mock.invalid/v1/parse")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == key.value)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["now"] as? String == "2026-11-08T18:07:00+07:00")
        let context = try #require(json["context"] as? [String: Any])
        #expect(Set(context.keys) == ["draftId", "answeringFieldId", "currentDraft"])  // nulls written out
        #expect(context.values.allSatisfy { $0 is NSNull })
    }

    @Test func parseRetryReusesTheSameKey() async throws {
        let transport = StubTransport { _, index in
            if index == 0 { throw URLError(.timedOut) }
            if index == 1 { return reply(503, envelope(APIErrorCode.upstreamError, retryable: true)) }
            return reply(200, Self.parseOK)
        }
        let key = IdempotencyKey()
        _ = try await makeClient(transport).parse(Self.parseRequest(), idempotencyKey: key)
        #expect(transport.requests.count == 3)
        #expect(Set(transport.requests.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }) == [key.value])
    }

    @Test(arguments: [(502, APIErrorCode.llmInvalidOutput), (503, APIErrorCode.spendCap), (402, "quota_exceeded"),
                      (413, "payload_too_large"), (422, "invalid_input")])
    func parseErrorsNotRetried(status: Int, code: String) async {
        let transport = StubTransport { _, _ in reply(status, envelope(code)) }
        await #expect(throws: AppError.self) {
            try await makeClient(transport).parse(Self.parseRequest(), idempotencyKey: IdempotencyKey())
        }
        #expect(transport.requests.count == 1)
    }

    @Test func parsePublishesQuota() async throws {
        let transport = StubTransport { _, _ in reply(200, Self.parseOK, headers: quotaHeaders) }
        let client = makeClient(transport)
        var updates = client.quotaUpdates.makeAsyncIterator()
        _ = try await client.parse(Self.parseRequest(), idempotencyKey: IdempotencyKey())
        #expect(try #require(await updates.next()).remaining == 7)
    }

    @Test func mockParseRecordsCalls() async throws {
        let mock = MockAPIClient()
        let key = IdempotencyKey()
        let draft = try await mock.parse(Self.parseRequest(), idempotencyKey: key)
        #expect(draft == .mockSMS)
        #expect(mock.parseCalls.map(\.key) == [key])
        let failing = MockAPIClient(parse: .failure(.api(code: APIErrorCode.llmInvalidOutput, retryable: true,
                                                          details: nil, requestId: nil)))
        await #expect(throws: AppError.self) { try await failing.parse(Self.parseRequest(), idempotencyKey: key) }
    }

    @Test func meSendsHeadersAndDecodes() async throws {
        let transport = StubTransport { _, _ in reply(200, meJSON, headers: quotaHeaders) }
        let me = try await makeClient(transport).me()

        #expect(me.userId == UUID(uuidString: "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11"))
        #expect(me.plan == .free && me.quota.remaining == 7)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.mock.invalid/v1/me")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0")
        #expect(request.value(forHTTPHeaderField: "X-Client-Version") == "1.0.0(1)")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "vi")
        #expect(request.timeoutInterval == 20)
    }

    @Test func healthHasNoAuthorization() async throws {
        let transport = StubTransport { _, _ in reply(200, #"{"status":"ok","version":"0.1.0","schemaVersion":1}"#) }
        let health = try await makeClient(transport).health()
        #expect(health == HealthResponse(status: "ok", version: "0.1.0", schemaVersion: 1))
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func quotaHeadersArePublished() async throws {
        let transport = StubTransport { _, _ in reply(200, meJSON, headers: quotaHeaders) }
        let client = makeClient(transport)
        var updates = client.quotaUpdates.makeAsyncIterator()
        _ = try await client.me()
        let quota = try #require(await updates.next())
        #expect(quota.limit == 10 && quota.remaining == 7 && quota.used == 3)
        #expect(quota.resetsAt == ISO8601DateFormatter().date(from: "2026-11-10T00:00:00+07:00"))
    }

    @Test func internalErrorRetriesTwiceThenThrows() async {
        let sleeps = SleepRecorder()
        let transport = StubTransport { _, _ in reply(500, envelope(APIErrorCode.internal, retryable: true)) }
        await #expect(throws: AppError.api(code: APIErrorCode.internal, retryable: true, details: nil, requestId: "req_env")) {
            try await makeClient(transport, sleeps: sleeps).me()
        }
        #expect(transport.requests.count == 3)
        #expect(sleeps.durations == [.seconds(1), .seconds(3)])
    }

    @Test func upstreamErrorThenSuccess() async throws {
        let transport = StubTransport { _, index in
            index == 0 ? reply(503, envelope(APIErrorCode.upstreamError, retryable: true)) : reply(200, meJSON)
        }
        _ = try await makeClient(transport).me()
        #expect(transport.requests.count == 2)
    }

    @Test(arguments: [(502, APIErrorCode.llmInvalidOutput), (503, APIErrorCode.spendCap), (422, "invalid_input")])
    func notRetried(status: Int, code: String) async {
        let transport = StubTransport { _, _ in reply(status, envelope(code)) }
        await #expect(throws: AppError.self) { try await makeClient(transport).me() }
        #expect(transport.requests.count == 1)
    }

    @Test func networkTimeoutIsRetried() async throws {
        let transport = StubTransport { _, index in
            if index == 0 { throw URLError(.timedOut) }
            return reply(200, meJSON)
        }
        _ = try await makeClient(transport).me()
        #expect(transport.requests.count == 2)
    }

    @Test func offlineFailsFast() async {
        let transport = StubTransport { _, _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: AppError.network(.offline)) { try await makeClient(transport).me() }
        #expect(transport.requests.count == 1)
    }

    @Test func unauthorizedRefreshesOnceAndRetries() async throws {
        let auth = FakeAuth()
        let transport = StubTransport { request, _ in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer t1"
                ? reply(200, meJSON) : reply(401, envelope(APIErrorCode.unauthorized))
        }
        _ = try await makeClient(transport, auth: auth).me()
        #expect(auth.refreshes == 1 && auth.signOuts == 0)
        #expect(transport.requests.count == 2)
    }

    @Test func unauthorizedTwiceSignsOut() async {
        let auth = FakeAuth()
        let transport = StubTransport { _, _ in reply(401, envelope(APIErrorCode.unauthorized)) }
        await #expect(throws: AppError.self) { try await makeClient(transport, auth: auth).me() }
        #expect(auth.refreshes == 1 && auth.signOuts == 1)
        #expect(transport.requests.count == 2)
    }

    @Test func refreshFailureSignsOut() async {
        let auth = FakeAuth(refreshFails: true)
        let transport = StubTransport { _, _ in reply(401, envelope(APIErrorCode.unauthorized)) }
        await #expect(throws: AppError.service(.unavailable(AuthErrorCode.notSignedIn))) {
            try await makeClient(transport, auth: auth).me()
        }
        #expect(auth.signOuts == 1 && transport.requests.count == 1)
    }

    @Test func parallelUnauthorizedShareOneRefresh() async throws {
        let auth = FakeAuth()
        let transport = StubTransport { request, _ in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer t1"
                ? reply(200, meJSON) : reply(401, envelope(APIErrorCode.unauthorized))
        }
        let client = makeClient(transport, auth: auth)
        async let first = client.me()
        async let second = client.me()
        _ = try await (first, second)
        #expect(auth.refreshes == 1)
        #expect(transport.requests.count == 4)
    }

    @Test func clientOutdatedPublishesBlockingScreen() async throws {
        let transport = StubTransport { _, _ in
            reply(426, envelope(APIErrorCode.clientOutdated, details: #"{"minVersion":"1.2.0"}"#))
        }
        let client = makeClient(transport)
        var updates = client.blockingUpdates.makeAsyncIterator()
        await #expect(throws: AppError.self) { try await client.me() }
        #expect(await updates.next() == .clientOutdated(minVersion: "1.2.0"))
        #expect(transport.requests.count == 1)
    }

    @Test func nonEnvelopeErrorIsDecodingError() async {
        let transport = StubTransport { _, _ in reply(502, "<html>Bad Gateway</html>") }
        await #expect(throws: AppError.decoding(requestId: "req_test")) { try await makeClient(transport).me() }
        #expect(transport.requests.count == 1)
    }

    @Test func badSuccessBodyIsDecodingError() async {
        let transport = StubTransport { _, _ in reply(200, #"{"schemaVersion":1}"#) }
        await #expect(throws: AppError.decoding(requestId: "req_test")) { try await makeClient(transport).me() }
    }

    @Test func cancelledURLErrorBecomesCancellation() async {
        let transport = StubTransport { _, _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) { try await makeClient(transport).me() }
        #expect(transport.requests.count == 1)
    }

    @Test func acceptLanguageFollowsDevice() {
        #expect(ClientInfo.language(preferred: ["en-US", "vi-VN"]) == "en")
        #expect(ClientInfo.language(preferred: ["vi-VN"]) == "vi")
        #expect(ClientInfo.language(preferred: ["fr-FR"]) == "vi")
        #expect(ClientInfo.language(preferred: []) == "vi")
    }

    @Test func idempotencyKeyIsLowercaseUUID() {
        let key = IdempotencyKey()
        #expect(key.value == key.value.lowercased())
        #expect(UUID(uuidString: key.value) != nil)
        #expect(IdempotencyKey() != key)
    }
}
