import Foundation
import Synchronization

/// In-memory `PurchaseService` for previews and tests (D-206). Prices are "Dữ liệu mẫu" (D-189).
final class MockPurchaseService: PurchaseService {
    static let sample = [
        ProductInfo(id: PremiumProducts.monthly, displayName: "Premium theo tháng", displayPrice: "19.000 ₫", period: .month),
        ProductInfo(id: PremiumProducts.yearly, displayName: "Premium theo năm", displayPrice: "190.000 ₫", period: .year),
    ]

    private struct State {
        var outcome: PurchaseOutcome = .verified(jws: "jws.mock")
        var entitlements: [String] = []
        var finished: [String] = []
        var purchases: [(id: String, token: UUID)] = []
    }

    private let state = Mutex(State())
    private let products: Result<[ProductInfo], ServiceError>
    private let updates = Broadcast<String>()

    init(products: Result<[ProductInfo], ServiceError> = .success(MockPurchaseService.sample)) {
        self.products = products
    }

    func setOutcome(_ outcome: PurchaseOutcome) { state.withLock { $0.outcome = outcome } }
    func setEntitlements(_ jws: [String]) { state.withLock { $0.entitlements = jws } }
    var finished: [String] { state.withLock { $0.finished } }
    var purchaseCalls: [(id: String, token: UUID)] { state.withLock { $0.purchases } }
    /// Tests: a renewal / Ask to Buy approval arriving later.
    func sendUpdate(_ jws: String) { updates.yield(jws) }

    func products() async throws -> [ProductInfo] { try products.get() }

    func purchase(_ id: String, appAccountToken: UUID) async throws -> PurchaseOutcome {
        state.withLock { $0.purchases.append((id, appAccountToken)); return $0.outcome }
    }

    func currentEntitlementJWS() async -> [String] { state.withLock { $0.entitlements } }
    var transactionUpdates: AsyncStream<String> { updates.stream }
    func finish(jws: String) async { state.withLock { $0.finished.append(jws) } }
}
