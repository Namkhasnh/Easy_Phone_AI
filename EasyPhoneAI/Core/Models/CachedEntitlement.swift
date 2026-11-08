import Foundation

/// DATA_MODEL §5. Display only — the device never decides entitlement (D-085).
struct CachedEntitlement: Codable, Sendable, Hashable {
    var plan: Plan
    var quotaRemaining: Int
    var resetsAt: Date
    var fetchedAt: Date
}

enum Plan: String, Codable, Sendable, Hashable {
    case free, premium
}
