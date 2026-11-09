import SwiftUI

/// Full-width primary action, ≥ 56pt (UI_SCREENS §2, D-182).
/// Disabled = `surface` fill + `textSecondary` text (never hidden). `isLoading` shows a `ProgressView` and disables.
/// `role: .destructive` (`danger` fill) comes with the `danger` token in 1A.10.
struct PrimaryButton: View {
    let titleKey: LocalizedStringKey
    var isLoading = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ titleKey: LocalizedStringKey, isLoading: Bool = false, action: @escaping () -> Void) {
        self.titleKey = titleKey
        self.isLoading = isLoading
        self.action = action
    }

    private var active: Bool { isEnabled && !isLoading }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s) {
                if isLoading {
                    ProgressView()
                        .tint(active ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                }
                Text(titleKey)
                    .font(Tokens.Fonts.button)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(active ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.buttonMinHeight)
            .padding(.horizontal, Tokens.Space.l)
            .background(active ? Tokens.Colors.primary : Tokens.Colors.surface,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.button))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: Tokens.Space.l) {
        PrimaryButton("common.confirm") {}
        PrimaryButton("common.confirm", isLoading: true) {}
        PrimaryButton("common.confirm") {}.disabled(true)
    }
    .padding(Tokens.Space.screenPadding)
}
