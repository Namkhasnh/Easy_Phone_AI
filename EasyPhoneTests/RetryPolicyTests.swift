import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("RetryPolicy (D-127, ARCHITECTURE §10)")
struct RetryPolicyTests {
    private let policy = RetryPolicy(jitter: { 0.5 })

    private static func api(_ code: String, details: APIErrorDetails? = nil) -> AppError {
        .api(code: code, retryable: true, details: details, requestId: nil)
    }

    @Test(arguments: [
        AppError.network(.timeout), .network(.other),
        api(APIErrorCode.internal), api(APIErrorCode.upstreamError),
    ])
    func transientRetriesTwiceWithBackoff(error: AppError) {
        var counts = RetryPolicy.Counts()
        #expect(policy.decide(error, retryAfter: nil, counts: &counts) == .retry(after: .seconds(1.5)))
        #expect(policy.decide(error, retryAfter: nil, counts: &counts) == .retry(after: .seconds(3.5)))
        #expect(policy.decide(error, retryAfter: nil, counts: &counts) == .stop)
    }

    @Test func jitterStaysWithinHalfSecond() {
        let policy = RetryPolicy()
        for _ in 0..<50 {
            var counts = RetryPolicy.Counts()
            guard case .retry(let delay) = policy.decide(.network(.timeout), retryAfter: nil, counts: &counts) else {
                Issue.record("expected retry"); return
            }
            #expect(delay >= .seconds(1) && delay <= .seconds(1.5))
        }
    }

    @Test(arguments: [
        AppError.network(.offline), .network(.tls), .decoding(requestId: nil),
        .service(.unavailable(AuthErrorCode.notSignedIn)),
        api(APIErrorCode.llmInvalidOutput), api(APIErrorCode.spendCap), api(APIErrorCode.quotaExceeded),
        api("billing_account_mismatch"), api("payload_too_large"), api("invalid_input"),
        api(APIErrorCode.clientOutdated), api(APIErrorCode.unauthorized), api("not_found"),
    ])
    func neverRetried(error: AppError) {
        var counts = RetryPolicy.Counts()
        #expect(policy.decide(error, retryAfter: nil, counts: &counts) == .stop)
    }

    @Test func rateLimitedWaitsRetryAfterOnce() {
        var counts = RetryPolicy.Counts()
        let error = Self.api(APIErrorCode.rateLimited)
        #expect(policy.decide(error, retryAfter: 4, counts: &counts) == .retry(after: .seconds(4)))
        #expect(policy.decide(error, retryAfter: 4, counts: &counts) == .stop)
    }

    @Test func rateLimitedFallsBackToDetailsAndStopsWhenTooLong() {
        var counts = RetryPolicy.Counts()
        let fromDetails = Self.api(APIErrorCode.rateLimited, details: APIErrorDetails(retryAfterSeconds: 7))
        #expect(policy.decide(fromDetails, retryAfter: nil, counts: &counts) == .retry(after: .seconds(7)))

        var fresh = RetryPolicy.Counts()
        #expect(policy.decide(Self.api(APIErrorCode.rateLimited), retryAfter: 3600, counts: &fresh) == .stop)
        var edge = RetryPolicy.Counts()
        #expect(policy.decide(Self.api(APIErrorCode.rateLimited), retryAfter: 30, counts: &edge)
                == .retry(after: .seconds(30)))
    }
}
