import Foundation

/// iOS error taxonomy (ARCHITECTURE §9.1). Every case maps to a stable `code` → `error.<code>` (D-249).
enum AppError: Error, Sendable, Hashable {
    /// Offline, timeout, TLS — no HTTP response.
    case network(NetworkFailure)
    /// Non-2xx with the API_CONTRACT §3.1 envelope.
    case api(code: String, retryable: Bool, details: APIErrorDetails?, requestId: String?)
    /// Device framework / SDK failure (e.g. no session for the token).
    case service(ServiceError)
    /// Response did not match the contract (a bug, or a proxy page instead of JSON). Log `requestId`.
    case decoding(requestId: String?)

    var code: String {
        switch self {
        case .network(let failure): "network.\(failure.rawValue)"
        case .api(let code, _, _, _): code
        case .service(let error): error.code
        case .decoding: "decoding"
        }
    }
}

enum NetworkFailure: String, Sendable, Hashable {
    case offline, timeout, tls, other

    init(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            self = .offline
        case .timedOut:
            self = .timeout
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            self = .tls
        default:
            self = .other
        }
    }
}

/// API_CONTRACT §3.2 codes the client branches on.
enum APIErrorCode {
    static let unauthorized = "unauthorized"
    static let quotaExceeded = "quota_exceeded"
    static let clientOutdated = "client_outdated"
    static let rateLimited = "rate_limited"
    static let `internal` = "internal"
    static let llmInvalidOutput = "llm_invalid_output"
    static let upstreamError = "upstream_error"
    static let spendCap = "spend_cap"
}
