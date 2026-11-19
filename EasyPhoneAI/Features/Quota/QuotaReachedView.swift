import SwiftUI

/// S17 Quota reached — Premium (sheet, D-241): hourglass · title · "Lượt mới có lúc {time}, {date}." · what still
/// works · Primary "Đã hiểu". No paywall for a subscriber.
struct QuotaReachedView: View {
    let quota: Quota?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Tokens.Space.l) {
            Image(systemName: "hourglass")
                .font(.system(size: Tokens.Size.iconHero))
                .foregroundStyle(Tokens.Colors.primary)
                .accessibilityHidden(true)
            Text("quota.premium.title")
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
            if let body = Self.body(quota) {
                Text(verbatim: body)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            }
            Text("quota.stillWorks")
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton("quota.ok") { dismiss() }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Tokens.Space.screenPadding)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("screen.S17")
    }

    /// "Lượt mới có lúc 00:00, 19/11."
    static func body(_ quota: Quota?) -> String? {
        guard let resetsAt = quota?.resetsAt else { return nil }
        return UserMessage(key: "quota.premium.body",
                           args: [resetsAt.formatted(date: .omitted, time: .shortened),
                                  resetsAt.formatted(.dateTime.day().month(.twoDigits))]).text
    }
}

/// The sheet for a `QuotaBlock`: S16 with the 402 context for free users, S17 for premium (D-088, D-241).
struct QuotaBlockSheet: View {
    let block: QuotaBlock
    @Environment(\.appEnv) private var env
    @Environment(AppState.self) private var appState

    var body: some View {
        switch block {
        case .paywall(let quota):
            PaywallView(viewModel: PaywallViewModel(purchases: env.purchases, api: env.api, userId: userId,
                                                    context: quota, onPlan: { appState.apply(me: $0) }))
        case .premiumLimit(let quota):
            QuotaReachedView(quota: quota)
        }
    }

    private var userId: UUID? {
        if case .signedIn(let id) = appState.session { id } else { nil }
    }
}

#Preview("S17") { QuotaReachedView(quota: Quota(limit: 300, used: 300, remaining: 0, resetsAt: .now)) }
