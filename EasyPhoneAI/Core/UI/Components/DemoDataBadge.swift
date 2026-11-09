import SwiftUI

/// "Dữ liệu mẫu" badge shown on previews and demo data (D-189, UI_SCREENS §0 rule 7).
struct DemoDataBadge: View {
    var body: some View {
        Label("common.demoData", systemImage: "testtube.2")
            .font(Tokens.Fonts.label)
            .foregroundStyle(Tokens.Colors.textPrimary)
            .padding(.horizontal, Tokens.Space.m)
            .padding(.vertical, Tokens.Space.xs)
            .background(Tokens.Colors.surface, in: Capsule())
    }
}

#Preview {
    DemoDataBadge()
}
