import SwiftUI

/// 1G.6 (D-188 relaxed by D-284): Privacy policy and Terms as in-app text, no public URL. Opened from S15 "Thông tin"
/// and the S16 links. The text describes what the app really does with data (D-056, D-059, D-187, D-304).
// TODO(spec): UI_SCREENS names only the link keys; the screen layout and texts are drafted here (owner to review).
struct LegalView: View {
    enum Document: String, Identifiable, Sendable {
        case privacy, terms
        var id: String { rawValue }
        var titleKey: LocalizedStringKey { self == .privacy ? "settings.privacy" : "settings.terms" }
        var bodyKey: LocalizedStringKey { self == .privacy ? "legal.privacy.body" : "legal.terms.body" }
    }

    let document: Document
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.bodyKey)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tokens.Space.screenPadding)
                    .textSelection(.enabled)
            }
            .background(Tokens.Colors.bg)
            .navigationTitle(Text(document.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("common.close") { dismiss() } }
            }
        }
        .accessibilityIdentifier("screen.legal.\(document.rawValue)")
    }
}

#Preview("Privacy") { LegalView(document: .privacy) }
#Preview("Terms, AX5") { LegalView(document: .terms).dynamicTypeSize(.accessibility5) }
