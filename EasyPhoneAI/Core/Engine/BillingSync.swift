import Foundation

/// API_CONTRACT §8.1 finish rules (D-083, D-085): every StoreKit transaction goes to the backend; the plan comes back.
/// `200` → finish + new entitlement; `403 billing_account_mismatch` → finish (it will never verify for this
/// account); network error, `400`, `5xx` → leave unfinished so StoreKit delivers it again on the next launch.
@MainActor enum BillingSync {
    static func verify(_ jws: String, api: any APIClientProtocol, purchases: any PurchaseService) async -> MeResponse? {
        do {
            let me = try await api.verifyTransaction(jws: jws)
            await purchases.finish(jws: jws)
            return me
        } catch let error as AppError {
            if error.code == "billing_account_mismatch" { await purchases.finish(jws: jws) }
            return nil
        } catch {
            return nil
        }
    }
}
