import SwiftUI

/// Full-width secondary action, same size as `PrimaryButton` (UI_SCREENS §2): `secondaryFill` + `primary` text.
/// Increase Contrast → `surface` fill + 2pt `primary` border (§1.1 rules). `role: .destructive` → `danger` text
/// (S11 "Xóa"; `danger` on `secondaryFill` / `surface` is in the contrast test).
struct SecondaryButton: View {
    let titleKey: LocalizedStringKey
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ titleKey: LocalizedStringKey, systemImage: String? = nil, role: ButtonRole? = nil,
         action: @escaping () -> Void) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    private var increased: Bool { contrast == .increased }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.button)
        Button(role: role, action: action) {
            HStack(spacing: Tokens.Space.s) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(titleKey)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Tokens.Fonts.button)
            .foregroundStyle(!isEnabled ? Tokens.Colors.textSecondary
                             : role == .destructive ? Tokens.Colors.danger : Tokens.Colors.primary)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.buttonMinHeight)
            .padding(.horizontal, Tokens.Space.l)
            .background(increased || !isEnabled ? Tokens.Colors.surface : Tokens.Colors.secondaryFill, in: shape)
            .overlay {
                if increased {
                    shape.strokeBorder(role == .destructive ? Tokens.Colors.danger : Tokens.Colors.primary, lineWidth: Tokens.Size.borderIncreasedContrast)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// Increase Contrast: use the canvas "Variants › Color Scheme Contrast" (the environment value is read-only).
#Preview("Light") {
    VStack(spacing: Tokens.Space.l) {
        SecondaryButton("common.edit") {}
        SecondaryButton("home.camera", systemImage: "camera") {}
        SecondaryButton("common.cancel") {}.disabled(true)
    }
    .padding(Tokens.Space.screenPadding)
    .background(Tokens.Colors.bg)
}

#Preview("Dark") {
    VStack(spacing: Tokens.Space.l) {
        SecondaryButton("common.edit") {}
    }
    .padding(Tokens.Space.screenPadding)
    .background(Tokens.Colors.bg)
    .preferredColorScheme(.dark)
}
