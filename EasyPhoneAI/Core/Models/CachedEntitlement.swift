import Foundation

/// DATA_MODEL §5. Display only — the device never decides entitlement (D-085).
struct CachedEntitlement: Codable, Sendable, Hashable {
    var plan: Plan
    var quotaRemaining: Int
    var resetsAt: Date
    var fetchedAt: Date
    /// Daily limit for "{remaining}/{limit}" (S15 AC7); nil in data saved before 1F.8.
    var quotaLimit: Int? = nil
}

/// A `402 quota_exceeded` (D-088, D-241): free → S16 with the context banner; premium → S17.
enum QuotaBlock: Identifiable, Sendable, Hashable {
    case paywall(Quota?)
    case premiumLimit(Quota?)

    var id: String {
        switch self {
        case .paywall: "paywall"
        case .premiumLimit: "premiumLimit"
        }
    }

    /// From the 402 details; nil for any other error.
    static func from(_ error: any Error) -> QuotaBlock? {
        guard case .api(let code, _, let details, _)? = error as? AppError, code == APIErrorCode.quotaExceeded
        else { return nil }
        return details?.plan == .premium ? .premiumLimit(details?.quota) : .paywall(details?.quota)
    }
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
