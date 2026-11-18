import SwiftUI

/// S16 Paywall (sheet, UI_SCREENS S16): "Để sau" · title · subtitle · 402 context · 3 benefits · 2 plan cards (radio,
/// 88pt, StoreKit price) · renewal text · Primary "Đăng ký" · Secondary "Để sau" · restore / Terms / Privacy links.
struct PaywallView: View {
    @State var viewModel: PaywallViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    Text("paywall.title")
                        .font(Tokens.Fonts.display)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("paywall.subtitle")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    if let context = viewModel.contextMessage {
                        Banner(message: context, style: .warning)
                    }
                    benefits
                    plans
                    Text("paywall.renewal")
                        .font(Tokens.Fonts.caption)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    if let message = viewModel.message {
                        Text(verbatim: message.text)
                            .font(Tokens.Fonts.body.weight(.semibold))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                    }
                    PrimaryButton("paywall.subscribe", isLoading: viewModel.isBusy) { Task { await viewModel.subscribe() } }
                        .disabled(viewModel.phase != .ready || viewModel.isBusy)
                    SecondaryButton("common.later") { dismiss() }
                    TextLinkButton("paywall.restore") { Task { await viewModel.restore() } }
                    // TODO(spec): Terms / Privacy open the in-app texts of 1G.6 (D-284); links shown, no target yet.
                    HStack(spacing: Tokens.Space.l) {
                        TextLinkButton("settings.terms") {}
                        TextLinkButton("settings.privacy") {}
                    }
                }
                .padding(Tokens.Space.screenPadding)
            }
            .background(Tokens.Colors.bg)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.later") { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.didSucceed) { _, done in
            guard done else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))                  // let "Bạn đã là thành viên Premium" be read
                dismiss()
            }
        }
        .accessibilityIdentifier("screen.S16")
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            benefit(Text(verbatim: UserMessage(key: "paywall.benefit.quota", args: ["\(PaywallViewModel.premiumLimit)"]).text))
            benefit(Text("paywall.benefit.all"))
            benefit(Text("paywall.benefit.same"))
        }
    }

    private func benefit(_ text: Text) -> some View {
        Label {
            text.font(Tokens.Fonts.body).foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.Colors.success)
        }
    }

    @ViewBuilder private var plans: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 88)
        case .unavailable:
            Text("paywall.productsUnavailable")
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
        case .ready:
            VStack(spacing: Tokens.Space.m) {
                ForEach(viewModel.products) { product in
                    planCard(product)
                }
            }
        }
    }

    private func planCard(_ product: ProductInfo) -> some View {
        let selected = viewModel.selectedId == product.id
        return Button { viewModel.selectedId = product.id } label: {
            HStack(spacing: Tokens.Space.m) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Tokens.Colors.primary : Tokens.Colors.border)
                Text(verbatim: PaywallViewModel.planTitle(product))
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.l)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Tokens.Colors.primary : Tokens.Colors.border, lineWidth: selected ? 3 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

#Preview("S16") {
    PaywallView(viewModel: PaywallViewModel(purchases: MockPurchaseService(), api: MockAPIClient(), userId: UUID(),
                                            context: Quota(limit: 10, used: 10, remaining: 0, resetsAt: .now)))
}
