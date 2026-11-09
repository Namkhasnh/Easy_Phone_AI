import SwiftUI

/// S19 Update required (426, blocking) — UI_SCREENS S19. One primary button (D-183), no close button.
struct UpdateRequiredView: View {
    @State private var viewModel: UpdateRequiredViewModel

    init(viewModel: UpdateRequiredViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.l) {
                // TODO(spec): S19 has no icon spec; SF Symbol at the hero size.
                Image(systemName: "arrow.down.app")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Tokens.Size.iconHero, height: Tokens.Size.iconHero)
                    .foregroundStyle(Tokens.Colors.primary)
                    .accessibilityHidden(true)

                Text("update.title")
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: viewModel.bodyText)   // localized in the ViewModel (`update.body`)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Space.screenPadding)
            .padding(.top, Tokens.Space.sectionGap)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("update.cta") { viewModel.openStore() }
                .padding(.horizontal, Tokens.Space.screenPadding)
                .padding(.vertical, Tokens.Space.m)
                .background(Tokens.Colors.bg)
        }
        .background(Tokens.Colors.bg)
        .interactiveDismissDisabled()   // UI_SCREENS §4: 426 blocks everything
    }
}

// MARK: - Previews (D-206; "Dữ liệu mẫu" badge, D-189)

private struct UpdateRequiredPreview: View {
    var minVersion = "1.2.0"

    var body: some View {
        UpdateRequiredView(viewModel: UpdateRequiredViewModel(minVersion: minVersion))
            .overlay(alignment: .topTrailing) { DemoDataBadge().padding() }
    }
}

#Preview("Mặc định") {
    UpdateRequiredPreview()
}

#Preview("AX5") {
    UpdateRequiredPreview()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Tối") {
    UpdateRequiredPreview()
        .preferredColorScheme(.dark)
}
