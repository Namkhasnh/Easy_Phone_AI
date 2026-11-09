import SwiftUI

/// Full-width primary action, ≥ 56pt (UI_SCREENS §2, D-182).
/// `role: .destructive` → `danger` fill. Disabled = `surface` fill + `textSecondary` text (never hidden), with
/// `disabledReasonKey` shown below (S04). `isLoading` shows a `ProgressView` and disables.
struct PrimaryButton: View {
    let titleKey: LocalizedStringKey
    var role: ButtonRole?
    var isLoading = false
    var disabledReasonKey: LocalizedStringKey?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ titleKey: LocalizedStringKey, role: ButtonRole? = nil, isLoading: Bool = false,
         disabledReasonKey: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.titleKey = titleKey
        self.role = role
        self.isLoading = isLoading
        self.disabledReasonKey = disabledReasonKey
        self.action = action
    }

    private var active: Bool { isEnabled && !isLoading }
    private var fill: Color {
        guard active else { return Tokens.Colors.surface }
        return role == .destructive ? Tokens.Colors.danger : Tokens.Colors.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Button(role: role, action: action) {
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
                .background(fill, in: RoundedRectangle(cornerRadius: Tokens.Radius.button))
                .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            if !isEnabled, let disabledReasonKey {
                Text(disabledReasonKey)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Light") {
    PrimaryButtonPreview()
}

#Preview("Dark, AX5") {
    PrimaryButtonPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct PrimaryButtonPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.l) {
                DemoDataBadge()
                PrimaryButton("common.confirm") {}
                PrimaryButton("common.confirm", isLoading: true) {}
                PrimaryButton("confirm.delete", role: .destructive) {}
                PrimaryButton("common.confirm", disabledReasonKey: "review.disabled.missing") {}.disabled(true)
            }
            .padding(Tokens.Space.screenPadding)
        }
        .background(Tokens.Colors.bg)
    }
}
