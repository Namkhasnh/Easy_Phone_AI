import Foundation
import Testing
@testable import EasyPhoneAI

/// 1F.6 — S16 Paywall (UI_SCREENS S16, D-083, D-085, D-088, D-089).
@MainActor
@Suite("S16 Paywall")
struct PaywallTests {
    let user = UUID()

    func model(_ store: MockPurchaseService = MockPurchaseService(), _ api: MockAPIClient = MockAPIClient(),
               context: Quota? = nil, onPlan: @escaping (MeResponse) -> Void = { _ in }) -> PaywallViewModel {
        PaywallViewModel(purchases: store, api: api, userId: user, context: context, onPlan: onPlan)
    }

    static let premium = MeResponse(schemaVersion: 1, userId: UUID(), locale: "vi", plan: .premium,
                                    quota: Quota(limit: 200, used: 0, remaining: 200, resetsAt: .now),
                                    subscription: nil)

    @Test func pricesOnlyFromStoreKit() async {
        let vm = model()
        await vm.load()
        #expect(vm.phase == .ready && vm.products.map(\.id) == PremiumProducts.all)
        #expect(PaywallViewModel.planTitle(vm.products[0]) == "Gói tháng — 49.000 ₫/tháng")
        #expect(PaywallViewModel.planTitle(vm.products[1]) == "Gói năm — 490.000 ₫/năm")

        let empty = model(MockPurchaseService(products: .failure(.framework(code: PurchaseErrorCode.productsUnavailable))))
        await empty.load()
        #expect(empty.phase == .unavailable && empty.products.isEmpty)               // no price invented (D-089)
        await empty.subscribe()
        #expect(empty.message == nil)                                                // nothing bought
    }

    @Test func subscribeVerifiesWithTheBackendThenClosesOnPremium() async throws {
        let store = MockPurchaseService(), api = MockAPIClient()
        api.setVerify(.success(Self.premium))
        var applied: MeResponse?
        let vm = model(store, api) { applied = $0 }
        await vm.load()
        vm.selectedId = PremiumProducts.yearly
        await vm.subscribe()
        let purchase = try #require(store.purchaseCalls.first)
        #expect(purchase.id == PremiumProducts.yearly && purchase.token == user)    // appAccountToken = user (D-083)
        #expect(api.verifyCalls == ["jws.mock"] && store.finished == ["jws.mock"])
        #expect(applied?.plan == .premium && vm.didSucceed)
        #expect(vm.message == UserMessage(key: "paywall.success"))
    }

    @Test func freePlanFromTheBackendIsNotSuccess() async {
        let vm = model()                                                             // MeResponse.mock = free
        await vm.load()
        await vm.subscribe()
        #expect(!vm.didSucceed)                                                      // the backend decides (D-085)
    }

    @Test func cancelPendingAndErrors() async {
        let store = MockPurchaseService(), api = MockAPIClient()
        let vm = model(store, api)
        await vm.load()
        store.setOutcome(.cancelled)
        await vm.subscribe()
        #expect(vm.message == nil && api.verifyCalls.isEmpty)
        store.setOutcome(.pending)
        await vm.subscribe()
        #expect(vm.message == UserMessage(key: "paywall.pending"))
        store.setOutcome(.verified(jws: "jws.x"))
        api.setVerify(.failure(.api(code: "billing_invalid", retryable: false, details: nil, requestId: nil)))
        await vm.subscribe()
        #expect(vm.message == UserMessage(key: "error.billing_invalid") && store.finished.isEmpty)
    }

    @Test func restore() async {
        let store = MockPurchaseService(), api = MockAPIClient()
        let vm = model(store, api)
        await vm.restore()
        #expect(vm.message == UserMessage(key: "paywall.restore.none"))
        store.setEntitlements(["jws.old"])
        api.setVerify(.success(Self.premium))
        await vm.restore()
        #expect(api.verifyCalls == ["jws.old"] && vm.didSucceed)
    }

    @Test func contextAndStrings() {
        let vm = model(context: Quota(limit: 10, used: 10, remaining: 0, resetsAt: .now))
        #expect(vm.contextMessage?.text.hasPrefix("Bạn đã dùng hết 10 lượt miễn phí hôm nay.") == true)
        for key in ["paywall.title", "paywall.subtitle", "paywall.benefit.quota", "paywall.benefit.all",
                    "paywall.benefit.same", "paywall.renewal", "paywall.subscribe", "paywall.restore",
                    "paywall.productsUnavailable", "settings.upgrade", "error.billing_invalid"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
        #expect(!UserMessage(key: "paywall.benefit.all").text.contains("ảnh"))       // photo reading is paused (D-302)
    }
}
