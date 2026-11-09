import Foundation

/// `GET /v1/me` (API_CONTRACT §6.2) = backend `schemas/me.py`. Unknown keys are ignored (§0.2);
/// unknown enum values decode to a fallback, never crash (§10, DATA_MODEL §12).
struct MeResponse: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let userId: UUID
    let locale: String
    let plan: Plan
    let quota: Quota
    let subscription: Subscription?
}

/// API_CONTRACT §4.5. `remaining = max(0, limit - used)`. Display only (D-085).
struct Quota: Codable, Sendable, Hashable {
    let limit: Int
    let used: Int
    let remaining: Int
    let resetsAt: Date
}

struct Subscription: Codable, Sendable, Hashable {
    let productId: String
    let status: SubscriptionStatus
    let expiresAt: Date?
    let environment: StoreEnvironment
}

/// DATA_MODEL §9 `subscriptions.status`.
enum SubscriptionStatus: String, Codable, Sendable, Hashable {
    case active, expired, inGracePeriod, billingRetry, revoked, refunded
    case unknown

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SubscriptionStatus(rawValue: raw) ?? .unknown
    }
}

/// DATA_MODEL §9 `subscriptions.environment`; `Xcode` only on the dev backend (D-240).
enum StoreEnvironment: String, Codable, Sendable, Hashable {
    case sandbox = "Sandbox"
    case production = "Production"
    case xcode = "Xcode"
    case unknown

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StoreEnvironment(rawValue: raw) ?? .unknown
    }
}
