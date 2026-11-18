import Foundation
import Testing
@testable import EasyPhoneAI

/// 1F.1 / 1F.2 — local `.storekit` file + `PurchaseService` + the API_CONTRACT §8.1 finish rules (D-083, D-085, D-284).
@MainActor
@Suite("Purchases (1F)", .serialized)
struct PurchaseTests {
    static let storeKitFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Config/EasyPhone.storekit")

    // MARK: - BillingSync finish rules

    @Test func okFinishesAndReturnsThePlan() async {
        let api = MockAPIClient(), store = MockPurchaseService()
        let me = await BillingSync.verify("jws.1", api: api, purchases: store)
        #expect(me == .mock && store.finished == ["jws.1"] && api.verifyCalls == ["jws.1"])
    }

    @Test func accountMismatchFinishesOthersStayForNextLaunch() async {
        let api = MockAPIClient(), store = MockPurchaseService()
        api.setVerify(.failure(.api(code: "billing_account_mismatch", retryable: false, details: nil, requestId: nil)))
        #expect(await BillingSync.verify("jws.403", api: api, purchases: store) == nil)
        #expect(store.finished == ["jws.403"])
        for error: AppError in [.api(code: "billing_invalid", retryable: false, details: nil, requestId: nil),
                                .network(.offline), .api(code: "internal", retryable: true, details: nil, requestId: nil)] {
            api.setVerify(.failure(error))
            #expect(await BillingSync.verify("jws.keep", api: api, purchases: store) == nil)
        }
        #expect(store.finished == ["jws.403"])                                      // never finished: redelivered
    }

    // The real StoreKit check against `Config/EasyPhone.storekit` is done by running the app from Xcode (scheme →
    // StoreKit Configuration) once the paywall exists (1F.6): `SKTestSession` returned no product even for a minimal
    // file in this hosted test target (probe 2026-11-18), so it cannot be a unit test here.
    @Test func productIdsMatchTheStoreKitFile() throws {
        let data = try Data(contentsOf: Self.storeKitFile)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = json["subscriptionGroups"] as? [[String: Any]] ?? []
        let ids = groups.flatMap { ($0["subscriptions"] as? [[String: Any]] ?? []).compactMap { $0["productID"] as? String } }
        #expect(ids == PremiumProducts.all)                                             // D-091, same as backend
        let periods = groups.flatMap { ($0["subscriptions"] as? [[String: Any]] ?? []).compactMap { $0["recurringSubscriptionPeriod"] as? String } }
        #expect(periods == ["P1M", "P1Y"])
    }
}
