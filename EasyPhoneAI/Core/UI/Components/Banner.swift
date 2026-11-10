import SwiftUI

/// Top-of-content notice (UI_SCREENS §2, §8): `surface` + 4pt left bar (`danger` / `warning`), icon + `body` text,
/// optional full-width `SecondaryButton` (e.g. "Thử lại").
struct Banner: View {
    enum Style: Sendable { case danger, warning }

    let message: UserMessage
    var style: Style = .danger
    var actionKey: LocalizedStringKey?
    var action: () -> Void = {}

    private var tint: Color { style == .danger ? Tokens.Colors.danger : Tokens.Colors.warning }
    // TODO(spec): UI_SCREENS §2 says "icon" without naming it; xmark.octagon (danger) / exclamationmark.triangle (warning).
    private var symbol: String { style == .danger ? "xmark.octagon" : "exclamationmark.triangle" }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(tint).frame(width: Tokens.Space.xs).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Label {
                    Text(verbatim: message.text)
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol)
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(tint)
                }
                if let actionKey {
                    SecondaryButton(actionKey, action: action)
                }
            }
            .padding(Tokens.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Light") {
    BannerPreview()
}

#Preview("Dark") {
    BannerPreview().preferredColorScheme(.dark)
}

private struct BannerPreview: View {
    var body: some View {
        VStack(spacing: Tokens.Space.l) {
            DemoDataBadge()
            Banner(message: UserMessage(key: "error.network.offline"), actionKey: "common.retry")
            Banner(message: UserMessage(key: "error.approval.mismatch"), style: .warning)
        }
        .padding(Tokens.Space.screenPadding)
        .background(Tokens.Colors.bg)
    }
}
