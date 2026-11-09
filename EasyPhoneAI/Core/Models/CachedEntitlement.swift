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

    /// Unknown raw value never crashes (API_CONTRACT §10).
    // TODO(spec): no fallback plan specified; `free` is safe because the value is display only (D-085).
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Plan(rawValue: raw) ?? .free
    }
}
