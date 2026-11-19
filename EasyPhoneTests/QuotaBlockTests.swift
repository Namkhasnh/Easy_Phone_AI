import Foundation
import Testing
@testable import EasyPhoneAI

/// 1F.7 / 1F.8 — 402 routing (D-088, D-241) and the quota row (S15 AC7, D-085 display only).
@MainActor
@Suite("Quota reached")
struct QuotaBlockTests {
    static let quota = Quota(limit: 30, used: 30, remaining: 0, resetsAt: Date(timeIntervalSince1970: 1_795_021_200))

    static func error(_ plan: Plan) -> AppError {
        .api(code: APIErrorCode.quotaExceeded, retryable: false,
             details: APIErrorDetails(plan: plan, quota: Self.quota), requestId: nil)
    }

    @Test func freeGetsThePaywallPremiumGetsS17() {
        #expect(QuotaBlock.from(Self.error(.free)) == .paywall(Self.quota))
        #expect(QuotaBlock.from(Self.error(.premium)) == .premiumLimit(Self.quota))
        #expect(QuotaBlock.from(AppError.network(.offline)) == nil)
        #expect(QuotaBlock.from(AppError.api(code: "internal", retryable: true, details: nil, requestId: nil)) == nil)
    }

    @Test func a402DuringParseOpensTheSheetAndKeepsTheText() async {
        let repo = MockTaskRepository()
        let draft = TaskDraft(inputMode: .text, originalInput: "Nhắc tôi uống thuốc lúc 8 giờ", timeZoneId: "Asia/Ho_Chi_Minh")
        repo.save(draft)
        let api = MockAPIClient(parse: .failure(Self.error(.free)))
        let vm = ConversationViewModel(draftId: draft.id, repository: repo, speech: MockSpeechService(), api: api,
                                       tts: MockTTSService(), localData: MockLocalDataRepository(),
                                       engine: TaskEngine(repository: repo))
        await vm.onAppear()
        #expect(vm.quotaBlock == .paywall(Self.quota))
        #expect(vm.text == "Nhắc tôi uống thuốc lúc 8 giờ")                        // nothing lost (D-104)
    }

    @Test func entitlementKeepsTheLimitForTheSettingsRow() {
        let state = AppState()
        state.apply(me: MeResponse(schemaVersion: 1, userId: UUID(), locale: "vi", plan: .free,
                                   quota: Quota(limit: 30, used: 5, remaining: 25, resetsAt: .now), subscription: nil))
        #expect(state.entitlement?.quotaLimit == 30 && state.entitlement?.quotaRemaining == 25)
        state.apply(quota: Quota(limit: 30, used: 6, remaining: 24, resetsAt: .now))
        #expect(state.entitlement?.quotaRemaining == 24)
        #expect(UserMessage(key: "settings.quota", args: ["24", "30"]).text == "Lượt AI còn lại hôm nay: 24/30")
    }

    @Test func s17TextAndStrings() {
        #expect(QuotaReachedView.body(Self.quota)?.hasPrefix("Lượt mới có lúc") == true)
        #expect(QuotaReachedView.body(nil) == nil)
        for key in ["quota.premium.title", "quota.premium.body", "quota.stillWorks", "quota.ok", "settings.quota.reset"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
    }
}
