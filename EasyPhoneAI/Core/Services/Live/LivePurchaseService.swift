import Foundation
import StoreKit
import Synchronization

/// StoreKit 2 (ARCHITECTURE §6.5). The only file that imports StoreKit (D-015). In Debug, Xcode runs it against
/// `Config/EasyPhone.storekit` (scheme → StoreKit Configuration, D-208, D-284); no App Store Connect needed.
final class LivePurchaseService: PurchaseService {
    /// Transactions handed out as JWS, kept until `finish(jws:)`.
    private let pending = Mutex<[String: Transaction]>([:])

    func products() async throws -> [ProductInfo] {
        let found: [Product]
        do {
            found = try await Product.products(for: PremiumProducts.all)
        } catch {
            throw ServiceError.framework(code: PurchaseErrorCode.productsUnavailable)
        }
        return found.map { product in
            ProductInfo(id: product.id, displayName: product.displayName, displayPrice: product.displayPrice,
                        period: product.subscription?.subscriptionPeriod.unit == .year ? .year : .month)
        }
        .sorted { PremiumProducts.all.firstIndex(of: $0.id) ?? 9 < PremiumProducts.all.firstIndex(of: $1.id) ?? 9 }
    }

    func purchase(_ id: String, appAccountToken: UUID) async throws -> PurchaseOutcome {
        guard let product = try? await Product.products(for: [id]).first else {
            throw ServiceError.framework(code: PurchaseErrorCode.productsUnavailable)
        }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        } catch {
            throw ServiceError.framework(code: PurchaseErrorCode.purchaseFailed)
        }
        switch result {
        case .success(let verification): return .verified(jws: keep(verification))
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: return .cancelled
        }
    }

    func latestJWS() async -> [String] {
        var all: [String] = []
        for id in PremiumProducts.all {
            if let verification = await Transaction.latest(for: id) { all.append(keep(verification)) }
        }
        return all
    }

    func currentEntitlementJWS() async -> [String] {
        var all: [String] = []
        for await verification in Transaction.currentEntitlements { all.append(keep(verification)) }
        return all
    }

    var transactionUpdates: AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates { continuation.yield(self.keep(verification)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func finish(jws: String) async {
        guard let transaction = pending.withLock({ $0.removeValue(forKey: jws) }) else { return }
        await transaction.finish()
    }

    /// The backend verifies the signature (API_CONTRACT §8.1); an unverified result is still sent, it will refuse it.
    private func keep(_ verification: VerificationResult<Transaction>) -> String {
        let transaction = verification.unsafePayloadValue
        pending.withLock { $0[verification.jwsRepresentation] = transaction }
        return verification.jwsRepresentation
    }
}
