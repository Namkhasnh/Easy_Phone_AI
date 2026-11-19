import SwiftUI

/// S16 Paywall (sheet, UI_SCREENS S16): "Để sau" · title · subtitle · 402 context · 3 benefits · 2 plan cards (radio,
/// 88pt, StoreKit price) · renewal text · Primary "Đăng ký" · Secondary "Để sau" · restore / Terms / Privacy links.
struct PaywallView: View {
    @State var viewModel: PaywallViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var legal: LegalView.Document?

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
                    comparisonTable
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
                    HStack(spacing: Tokens.Space.l) {                     // D-089: Terms + Privacy (1G.6 in-app text)
                        TextLinkButton("settings.terms") { legal = .terms }
                        TextLinkButton("settings.privacy") { legal = .privacy }
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
        .sheet(item: $legal) { LegalView(document: $0) }
        .onChange(of: viewModel.didSucceed) { _, done in
            guard done else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))                  // let "Bạn đã là thành viên Premium" be read
                dismiss()
            }
        }
        .accessibilityIdentifier("screen.S16")
    }

    /// D-314: Free / Premium side by side. Stacks into one card per row at accessibility text sizes.
    // TODO(spec): the table is not in UI_SCREENS S16 (owner 2026-11-18); it replaces the 3 benefit lines.
    private var comparisonTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "").frame(maxWidth: .infinity, alignment: .leading)
                header("paywall.col.free")
                header("paywall.col.premium")
            }
            .padding(.bottom, Tokens.Space.s)
            ForEach(PaywallViewModel.comparison) { row in
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(row.key)).frame(maxWidth: .infinity, alignment: .leading)
                        cell(row.free)
                        cell(row.premium, strong: true)
                    }
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text(LocalizedStringKey(row.key)).font(Tokens.Fonts.body.weight(.semibold))
                        Text(verbatim: "\(UserMessage(key: "paywall.col.free").text): \(row.free)")
                        Text(verbatim: "\(UserMessage(key: "paywall.col.premium").text): \(row.premium)")
                    }
                }
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .padding(.vertical, Tokens.Space.s)
                .accessibilityElement(children: .combine)
            }
            Text("paywall.allFree")
                .font(Tokens.Fonts.caption)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .padding(.top, Tokens.Space.s)
        }
        .padding(Tokens.Space.l)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Tokens.Fonts.label)
            .foregroundStyle(Tokens.Colors.textSecondary)
            .frame(width: 96, alignment: .center)
    }

    private func cell(_ text: String, strong: Bool = false) -> some View {
        Text(verbatim: text)
            .font(strong ? Tokens.Fonts.body.weight(.semibold) : Tokens.Fonts.body)
            .multilineTextAlignment(.center)
            .frame(width: 96)
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
