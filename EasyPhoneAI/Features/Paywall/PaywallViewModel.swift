import Foundation
import Observation

/// S16 Paywall (UI_SCREENS S16, D-083, D-085, D-089). Prices only from StoreKit; the plan only from the backend.
@Observable @MainActor final class PaywallViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// StoreKit returned nothing → `paywall.productsUnavailable`, no price shown (D-089).
        case unavailable
    }

    private(set) var phase: Phase = .loading
    private(set) var products: [ProductInfo] = []
    var selectedId: String = PremiumProducts.monthly
    private(set) var isBusy = false
    /// The line under the buttons: success, pending, "nothing to restore", or an error.
    private(set) var message: UserMessage?
    /// Premium confirmed by the backend → the sheet closes.
    private(set) var didSucceed = false
    /// From a free-user 402 (D-088): "Bạn đã dùng hết {limit} lượt miễn phí hôm nay…".
    let context: Quota?

    private let purchases: any PurchaseService
    private let api: any APIClientProtocol
    private let userId: UUID?
    private let onPlan: (MeResponse) -> Void

    init(purchases: any PurchaseService, api: any APIClientProtocol, userId: UUID?, context: Quota? = nil,
         onPlan: @escaping (MeResponse) -> Void = { _ in }) {
        self.purchases = purchases
        self.api = api
        self.userId = userId
        self.context = context
        self.onPlan = onPlan
    }

    func load() async {
        do {
            products = try await purchases.products()
            phase = products.isEmpty ? .unavailable : .ready
            if !products.contains(where: { $0.id == selectedId }), let first = products.first { selectedId = first.id }
        } catch {
            phase = .unavailable
        }
    }

    /// "Gói tháng — 49.000 ₫/tháng".
    static func planTitle(_ product: ProductInfo) -> String {
        UserMessage(key: product.period == .year ? "paywall.plan.yearly" : "paywall.plan.monthly",
                    args: [product.displayPrice]).text
    }

    var contextMessage: UserMessage? {
        guard let context else { return nil }
        let time = context.resetsAt.formatted(date: .omitted, time: .shortened)
        return UserMessage(key: "paywall.context.quota", args: ["\(context.limit)", time])
    }

    /// D-314 daily AI limits, shown in the comparison table (display only; the backend enforces them, D-085).
    // TODO(spec): no endpoint returns both limits; the D-314 values are mirrored here and must change with the backend.
    static let freeLimit = 30
    static let premiumLimit = 300

    /// One row of the Free / Premium table (D-314): every feature is free; Premium only raises the AI limit.
    struct Row: Hashable, Identifiable {
        let key: String
        let free: String
        let premium: String
        var id: String { key }
    }

    static var comparison: [Row] {
        let unlimited = UserMessage(key: "paywall.cell.unlimited").text
        let yes = UserMessage(key: "paywall.cell.yes").text
        let perDay = { (n: Int) in UserMessage(key: "paywall.cell.perDay", args: ["\(n)"]).text }
        return [
            Row(key: "paywall.row.device", free: unlimited, premium: unlimited),
            Row(key: "paywall.row.ai", free: perDay(freeLimit), premium: perDay(premiumLimit)),
            Row(key: "paywall.row.gmail", free: yes, premium: yes),
            Row(key: "paywall.row.voice", free: yes, premium: yes),
            Row(key: "paywall.row.ads", free: UserMessage(key: "paywall.cell.none").text,
                premium: UserMessage(key: "paywall.cell.none").text),
        ]
    }

    /// "Đăng ký": StoreKit → `/v1/billing/verify` → plan. Cancelling is not an error.
    func subscribe() async {
        guard !isBusy, phase == .ready, let userId else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await purchases.purchase(selectedId, appAccountToken: userId) {
            case .verified(let jws): await confirm([jws])
            case .pending: message = UserMessage(key: "paywall.pending")
            case .cancelled: break
            }
        } catch {
            message = UserMessage(key: "error.generic")
        }
    }

    /// "Khôi phục giao dịch": every current entitlement goes to the backend.
    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        let all = await purchases.currentEntitlementJWS()
        guard !all.isEmpty else { message = UserMessage(key: "paywall.restore.none"); return }
        await confirm(all)
    }

    private func confirm(_ jws: [String]) async {
        var last: AppError?
        for token in jws {
            switch await BillingSync.verifyResult(token, api: api, purchases: purchases) {
            case .success(let me):
                onPlan(me)
                if me.plan == .premium {
                    message = UserMessage(key: "paywall.success")
                    didSucceed = true
                    return
                }
            case .failure(let error):
                last = error
            }
        }
        message = last.map(Self.failure) ?? UserMessage(key: "paywall.restore.none")
    }

    static func failure(_ error: AppError) -> UserMessage {
        switch error {
        case .network: UserMessage(key: "error.network.offline")
        case .api(let code, _, _, _) where ["billing_invalid", "billing_account_mismatch"].contains(code):
            UserMessage(key: "error.\(code)")
        default: UserMessage(key: "error.generic")
        }
    }
}
