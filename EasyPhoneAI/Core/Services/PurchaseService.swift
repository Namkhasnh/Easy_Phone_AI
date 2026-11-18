import Foundation

/// StoreKit 2 behind a protocol (ARCHITECTURE §4.1, §6.5, D-015). The app never decides entitlement: every
/// transaction goes to `POST /v1/billing/verify` and the backend answers with the plan (D-083, D-085).
protocol PurchaseService: Sendable {
    /// Premium products, monthly first (ids from config, D-091). Prices only as StoreKit returns them (D-089).
    func products() async throws -> [ProductInfo]
    /// `appAccountToken` = the Supabase user id (D-083).
    func purchase(_ id: String, appAccountToken: UUID) async throws -> PurchaseOutcome
    /// "Khôi phục giao dịch": the signed transactions of every current entitlement.
    func currentEntitlementJWS() async -> [String]
    /// From `Transaction.updates`, observed from launch for the whole process (renewals, Ask to Buy, refunds).
    var transactionUpdates: AsyncStream<String> { get }
    /// After `200` / `403` from the backend (API_CONTRACT §8.1); never after a network error or `5xx`.
    func finish(jws: String) async
}

struct ProductInfo: Sendable, Hashable, Identifiable {
    enum Period: String, Sendable, Hashable { case month, year }

    let id: String
    let displayName: String
    /// Formatted by StoreKit for the storefront ("49.000 ₫"). Never built by the app (D-089).
    let displayPrice: String
    let period: Period
}

enum PurchaseOutcome: Sendable, Hashable {
    case verified(jws: String)
    case cancelled
    /// Ask to Buy / SCA: the answer comes later through `transactionUpdates`.
    case pending
}

/// Product ids (D-091); the same values as the backend's `PRODUCT_IDS` and `Config/EasyPhone.storekit`.
enum PremiumProducts {
    static let monthly = "easyphone.premium.monthly"
    static let yearly = "easyphone.premium.yearly"
    static let all = [monthly, yearly]
}

/// Error codes for `ServiceError.framework` (D-249).
enum PurchaseErrorCode {
    static let productsUnavailable = "storekit.productsUnavailable"
    static let purchaseFailed = "storekit.purchaseFailed"
}
