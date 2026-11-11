import Foundation

/// Automatic HTTP retries (API_CONTRACT §10, ARCHITECTURE §10, D-127). Pure: no clock, no I/O.
/// `401` is not handled here — `APIClient` refreshes once (§2).
struct RetryPolicy: Sendable {
    enum Decision: Sendable, Hashable {
        case retry(after: Duration)
        case stop
    }

    /// Retries already used for one call. Pass the same value back on every attempt.
    struct Counts: Sendable, Hashable {
        var transient = 0
        var rateLimited = 0
    }

    /// D-127: 2 retries, 1 s then 3 s (+ jitter).
    var backoff: [Double] = [1, 3]
    // TODO(spec): jitter size not specified (API_CONTRACT §10 "+ jitter"); 0–0.5 s.
    var jitter: @Sendable () -> Double = { Double.random(in: 0...0.5) }
    /// `429`: wait `Retry-After`, max 1 attempt.
    var maxRateLimitWaits = 1
    // TODO(spec): no upper bound on `Retry-After` in the docs; a longer wait is not retried at all (no hang, no 2nd 429).
    var maxRetryAfter: Double = 30

    func decide(_ error: AppError, retryAfter: Double?, counts: inout Counts) -> Decision {
        if Self.isTransient(error) {
            guard counts.transient < backoff.count else { return .stop }
            let delay = backoff[counts.transient] + jitter()
            counts.transient += 1
            return .retry(after: .seconds(delay))
        }
        if case .api(APIErrorCode.rateLimited, _, let details, _) = error {
            guard counts.rateLimited < maxRateLimitWaits else { return .stop }
            counts.rateLimited += 1
            let wait = retryAfter ?? details?.retryAfterSeconds.map(Double.init) ?? 1
            // Waiting less than the server asked only earns a second 429 (e.g. transcribe: 50 min) → stop now,
            // so the caller falls back at once (transcribe → keyboard, ARCHITECTURE §9.2).
            guard wait <= maxRetryAfter else { return .stop }
            return .retry(after: .seconds(max(wait, 0)))
        }
        // 402, 403, 413, 422, 426, 502, 503 spend_cap, other 4xx, decoding, service: never (ARCHITECTURE §10).
        return .stop
    }

    /// Network errors, `500 internal`, `503 upstream_error`. Offline and TLS fail fast: retrying cannot help
    /// and the offline message must come quickly (ARCHITECTURE §11).
    static func isTransient(_ error: AppError) -> Bool {
        switch error {
        case .network(let failure):
            failure == .timeout || failure == .other
        case .api(let code, _, _, _):
            code == APIErrorCode.internal || code == APIErrorCode.upstreamError
        case .service, .decoding:
            false
        }
    }
}
