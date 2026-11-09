import SwiftUI

/// Centered empty state (UI_SCREENS §2): hero icon (default `pawprint.fill`) on an 88pt `honey` circle (D-291),
/// `title` + optional `body`.
struct EmptyState: View {
    var systemImage = "pawprint.fill"
    let titleKey: LocalizedStringKey
    var bodyKey: LocalizedStringKey?

    var body: some View {
        VStack(spacing: Tokens.Space.l) {
            Image(systemName: systemImage)
                .font(.system(size: Tokens.Size.iconHero * 0.7))   // icon inside the fixed 88pt circle
                .foregroundStyle(Tokens.Colors.onHoney)
                .frame(width: 88, height: 88)
                .background(Tokens.Colors.honey, in: Circle())
                .accessibilityHidden(true)
            Text(titleKey)
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.textPrimary)
            if let bodyKey {
                Text(bodyKey)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Light") {
    EmptyState(titleKey: "history.empty")
        .background(Tokens.Colors.bg)
}

#Preview("Dark") {
    EmptyState(titleKey: "history.empty")
        .background(Tokens.Colors.bg)
        .preferredColorScheme(.dark)
}
