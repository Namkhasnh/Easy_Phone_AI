import Foundation
import OSLog

/// API_CONTRACT §8.1 finish rules (D-083, D-085): every StoreKit transaction goes to the backend; the plan comes back.
/// `200` → finish + new entitlement; `403 billing_account_mismatch` → finish (it will never verify for this
/// account); network error, `400`, `5xx` → leave unfinished so StoreKit delivers it again on the next launch.
@MainActor enum BillingSync {
    static func verify(_ jws: String, api: any APIClientProtocol, purchases: any PurchaseService) async -> MeResponse? {
        try? await verifyResult(jws, api: api, purchases: purchases).get()
    }

    /// Same rules; the error is kept for the paywall's message.
    static func verifyResult(_ jws: String, api: any APIClientProtocol,
                             purchases: any PurchaseService) async -> Result<MeResponse, AppError> {
        do {
            let me = try await api.verifyTransaction(jws: jws)
            await purchases.finish(jws: jws)
            return .success(me)
        } catch let error as AppError {
            logger.info("billing verify failed: \(error.code, privacy: .public)")       // code only (D-059)
            if error.code == "billing_account_mismatch" { await purchases.finish(jws: jws) }
            return .failure(error)
        } catch {
            logger.info("billing verify failed: decoding")
            return .failure(.decoding(requestId: nil))
        }
    }

    /// At launch / sign-in (owner 2026-11-22: a Transaction Manager refund never reached the backend): the latest
    /// transaction of each product goes to the backend again, so a missed refund, expiry or renewal is applied.
    /// Returns the last plan the backend answered, `nil` when nothing was sent or every call failed.
    static func reconcile(api: any APIClientProtocol, purchases: any PurchaseService) async -> MeResponse? {
        var last: MeResponse?
        for jws in await purchases.latestJWS() {
            if let me = await verify(jws, api: api, purchases: purchases) { last = me }
        }
        return last
    }

    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "billing")
}
