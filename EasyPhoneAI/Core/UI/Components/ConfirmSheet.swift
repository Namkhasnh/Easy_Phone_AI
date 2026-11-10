import SwiftUI

/// Every destructive confirm (UI_SCREENS §2, S20): medium/large detents, title, body, optional note,
/// destructive `PrimaryButton` + `SecondaryButton`, stacked. Delete always needs this tap (D-108).
struct ConfirmSheet: View {
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
    var noteKey: LocalizedStringKey?
    let confirmKey: LocalizedStringKey
    var cancelKey: LocalizedStringKey = "common.cancel"
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Text(titleKey)
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(bodyKey)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if let noteKey {
                    Text(noteKey)
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.screenPadding)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Tokens.Space.m) {
                PrimaryButton(confirmKey, role: .destructive, action: onConfirm)
                SecondaryButton(cancelKey, action: onCancel)
            }
            .padding(Tokens.Space.screenPadding)
            .background(Tokens.Colors.bg)
        }
        .background(Tokens.Colors.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Light") {
    ConfirmSheetPreview()
}

#Preview("Dark, AX5") {
    ConfirmSheetPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct ConfirmSheetPreview: View {
    var body: some View {
        DemoDataBadge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Colors.bg)
            .sheet(isPresented: .constant(true)) {
                ConfirmSheet(titleKey: "confirm.clearHistory.title", bodyKey: "confirm.clearHistory.body",
                             confirmKey: "confirm.delete", onConfirm: {}, onCancel: {})
            }
    }
}
