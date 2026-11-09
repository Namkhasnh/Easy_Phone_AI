import SwiftUI

/// Inline link-style action (UI_SCREENS §2): `primary` text, `body` font, ≥ 44pt tall
/// (legal links, "Xem tất cả", "Xem ảnh gốc").
struct TextLinkButton: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void

    init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.titleKey = titleKey
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Tokens.Size.tapTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(alignment: .leading) {
        TextLinkButton("common.seeAll") {}
        TextLinkButton("common.viewSourceImage") {}
    }
    .padding(Tokens.Space.screenPadding)
    .background(Tokens.Colors.bg)
}
