import Foundation
import OSLog

/// Live `APIClientProtocol` (API_CONTRACT §1, §2, §10; ARCHITECTURE §10).
/// An `actor` so parallel `401`s share one token refresh (ARCHITECTURE §8).
actor APIClient: APIClientProtocol {
    private struct Endpoint: Sendable {
        let method: String
        let path: String
        let authorized: Bool
        var body: Data?
        var contentType = "application/json; charset=utf-8"
        var idempotencyKey: IdempotencyKey?
    }

    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "api")

    private let config: AppConfig
    private let auth: any AuthService
    private let transport: any HTTPTransport
    private let client: ClientInfo
    private let retryPolicy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void
    private let quota = Broadcast<Quota>()
    private let blocking = Broadcast<BlockingScreen>()

    /// The refresh in flight, shared by every request that got a `401` meanwhile.
    private var refreshTask: Task<String, any Error>?
    /// Last completed refresh: a request that failed with `stale` just uses `fresh` (no second refresh).
    private var lastRefresh: (stale: String, fresh: String)?

    init(config: AppConfig,
         auth: any AuthService,
         transport: any HTTPTransport = URLSessionTransport(),
         client: ClientInfo,
         retryPolicy: RetryPolicy = RetryPolicy(),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.config = config
        self.auth = auth
        self.transport = transport
        self.client = client
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    nonisolated var quotaUpdates: AsyncStream<Quota> { quota.stream }
    nonisolated var blockingUpdates: AsyncStream<BlockingScreen> { blocking.stream }

    func health() async throws -> HealthResponse {
        try await send(Endpoint(method: "GET", path: "/v1/health", authorized: false))
    }

    func me() async throws -> MeResponse {
        try await send(Endpoint(method: "GET", path: "/v1/me", authorized: true))
    }

    func parse(_ request: ParseRequest, idempotencyKey: IdempotencyKey) async throws -> ParsedDraft {
        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            throw AppError.decoding(requestId: nil)  // cannot happen for these types; never sent half-built
        }
        // Same `Endpoint` (same key) for every automatic retry inside `send` (D-245).
        return try await send(Endpoint(method: "POST", path: "/v1/parse", authorized: true,
                                       body: body, idempotencyKey: idempotencyKey))
    }

    func transcribe(m4a: Data, meta: MediaMeta) async throws -> TranscribeResponse {
        var form = MultipartBody()
        let metaJSON: Data
        do {
            metaJSON = try JSONEncoder().encode(meta)
        } catch {
            throw AppError.decoding(requestId: nil)
        }
        form.addField("meta", String(decoding: metaJSON, as: UTF8.self))
        form.addFile("audio", filename: "speech.m4a", mimeType: "audio/mp4", m4a)
        let contentType = form.contentType
        return try await send(Endpoint(method: "POST", path: "/v1/transcribe", authorized: true,
                                       body: form.finish(), contentType: contentType))
    }

    // MARK: - Pipeline

    private func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        var counts = RetryPolicy.Counts()
        var refreshed = false
        var token = endpoint.authorized ? try await accessToken() : nil
        var attempt = 0

        while true {
            try Task.checkCancellation()
            attempt += 1
            let request = makeRequest(endpoint, token: token)

            let error: AppError
            var retryAfter: Double?
            do {
                let (data, http) = try await transport.send(request)
                let requestId = http.value(forHTTPHeaderField: "X-Request-Id")
                // D-059: ids and status only, never bodies.
                Self.logger.info("\(endpoint.method, privacy: .public) \(endpoint.path, privacy: .public) \(http.statusCode) attempt=\(attempt) \(requestId ?? "-", privacy: .public)")

                if (200..<300).contains(http.statusCode) {
                    if let quota = Self.quota(from: http) { self.quota.yield(quota) }
                    do {
                        return try Self.decoder().decode(Response.self, from: data)
                    } catch {
                        throw AppError.decoding(requestId: requestId)
                    }
                }
                error = Self.apiError(data, requestId: requestId)
                retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            } catch let urlError as URLError {
                if urlError.code == .cancelled { throw CancellationError() }
                Self.logger.info("\(endpoint.method, privacy: .public) \(endpoint.path, privacy: .public) network=\(urlError.code.rawValue) attempt=\(attempt)")
                error = .network(NetworkFailure(urlError))
            }

            if case .api(APIErrorCode.unauthorized, _, _, _) = error, let stale = token {
                // API_CONTRACT §2: refresh once and retry; still 401 → sign out (drafts kept, D-104).
                guard !refreshed else {
                    await auth.signOut()
                    throw error
                }
                refreshed = true
                token = try await refreshedToken(replacing: stale)
                continue
            }
            if case .api(APIErrorCode.clientOutdated, _, let details, _) = error {
                // UI_SCREENS §4: any 426 → S19. Never retried.
                // TODO(spec): 426 without `details.minVersion` — S19 gets an empty version.
                blocking.yield(.clientOutdated(minVersion: details?.minVersion ?? ""))
                throw error
            }
            switch retryPolicy.decide(error, retryAfter: retryAfter, counts: &counts) {
            case .stop:
                throw error
            case .retry(let delay):
                try await sleep(delay)
            }
        }
    }

    private func makeRequest(_ endpoint: Endpoint, token: String?) -> URLRequest {
        var request = URLRequest(url: config.apiBaseURL.appending(path: endpoint.path),
                                 timeoutInterval: URLSessionTransport.timeout)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-Client-Version")
        request.setValue(client.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let key = endpoint.idempotencyKey { request.setValue(key.value, forHTTPHeaderField: "Idempotency-Key") }
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue(endpoint.contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: - Token

    private func accessToken() async throws -> String {
        do {
            return try await auth.accessToken(forceRefresh: false)
        } catch let error as ServiceError {
            throw AppError.service(error)
        }
    }

    private func refreshedToken(replacing stale: String) async throws -> String {
        if let lastRefresh, lastRefresh.stale == stale { return lastRefresh.fresh }
        if let refreshTask { return try await Self.serviceErrors { try await refreshTask.value } }

        let auth = self.auth
        let task = Task { try await auth.accessToken(forceRefresh: true) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await Self.serviceErrors { try await task.value }
            lastRefresh = (stale, fresh)
            return fresh
        } catch {
            // Session cannot be refreshed → back to S01 (API_CONTRACT §2).
            await auth.signOut()
            throw error
        }
    }

    private static func serviceErrors<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as ServiceError {
            throw AppError.service(error)
        }
    }

    // MARK: - Decoding

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601   // API_CONTRACT §0.4: ISO 8601 with offset
        return decoder
    }

    /// Non-2xx body → `.api`; a body that is not the §3.1 envelope (e.g. a tunnel error page) → `.decoding`.
    static func apiError(_ data: Data, requestId: String?) -> AppError {
        guard let envelope = try? decoder().decode(APIErrorEnvelope.self, from: data) else {
            return .decoding(requestId: requestId)
        }
        let body = envelope.error
        return .api(code: body.code, retryable: body.retryable, details: body.details,
                    requestId: body.requestId ?? requestId)
    }

    /// `X-Quota-Limit`, `X-Quota-Remaining`, `X-Quota-Resets-At` (D-234). All three or nothing.
    static func quota(from http: HTTPURLResponse) -> Quota? {
        guard let limit = http.value(forHTTPHeaderField: "X-Quota-Limit").flatMap({ Int($0) }),
              let remaining = http.value(forHTTPHeaderField: "X-Quota-Remaining").flatMap({ Int($0) }),
              let rawResets = http.value(forHTTPHeaderField: "X-Quota-Resets-At"),
              let resetsAt = ISO8601DateFormatter().date(from: rawResets) else { return nil }
        return Quota(limit: limit, used: max(0, limit - remaining), remaining: remaining, resetsAt: resetsAt)
    }
}
