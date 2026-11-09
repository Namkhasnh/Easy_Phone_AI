import Foundation

/// Every non-2xx body (API_CONTRACT §3.1, D-233). The app shows `error.<code>`, never `message` when a key exists.
struct APIErrorEnvelope: Codable, Sendable, Hashable {
    let error: APIErrorBody
}

struct APIErrorBody: Codable, Sendable, Hashable {
    let code: String
    let message: String
    let retryable: Bool
    let requestId: String?
    let details: APIErrorDetails?
}

/// Union of the per-code `details` in API_CONTRACT §3.2; every key is optional.
struct APIErrorDetails: Codable, Sendable, Hashable {
    var plan: Plan?                 // 402
    var quota: Quota?               // 402
    var maxBytes: Int?              // 413
    var maxChars: Int?              // 413
    var field: String?              // 422
    var reason: String?             // 422
    var minVersion: String?         // 426
    var retryAfterSeconds: Int?     // 429
}
