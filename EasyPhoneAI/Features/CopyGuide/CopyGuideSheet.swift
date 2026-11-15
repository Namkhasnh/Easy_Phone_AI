import SwiftUI

/// What S07 shows (UI_SCREENS S07, D-162): the service, the copied text and its guide steps.
struct CopyGuide: Sendable, Hashable, Identifiable {
    let serviceName: String
    let body: String
    let steps: [String]
    var id: String { serviceName + body }
}

/// S07 Copy guide (channel not verified, D-162). Title · status card (`doc.on.doc` + `copy.status`) · message preview ·
/// numbered steps (56pt rows, big number circle) · Primary "Đã xong" · Secondary "Sao chép lại". Shown only after
/// "Xác nhận" on S04; the text is already copied (step `handedOff`). No contact permission on this path (D-247).
struct CopyGuideSheet: View {
    let guide: CopyGuide
    let onDone: () -> Void
    let onCopyAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Text(verbatim: UserMessage(key: "copy.title", args: [guide.serviceName]).text)
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Label {
                    Text(verbatim: UserMessage(key: "copy.status", args: [guide.serviceName]).text)
                } icon: {
                    Image(systemName: "doc.on.doc").accessibilityHidden(true)
                }
                .font(Tokens.Fonts.body.weight(.semibold))
                .foregroundStyle(Tokens.Colors.success)
                .padding(Tokens.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                Text(verbatim: guide.body)                                     // user data, not a UI literal
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .padding(Tokens.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                if !guide.steps.isEmpty {
                    Text("copy.stepsTitle")
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                        HStack(spacing: Tokens.Space.m) {
                            Text(verbatim: "\(index + 1)")
                                .font(Tokens.Fonts.button)
                                .foregroundStyle(Tokens.Colors.onPrimary)
                                .frame(width: Tokens.Size.stepBadge, height: Tokens.Size.stepBadge)
                                .background(Tokens.Colors.primary, in: Circle())
                                .accessibilityHidden(true)
                            Text(verbatim: text)                                // SupportedServices.json guide text (vi)
                                .font(Tokens.Fonts.fieldValue)
                                .foregroundStyle(Tokens.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: Tokens.Size.buttonMinHeight, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Tokens.Space.m) {
                PrimaryButton("common.yesDone", action: onDone)
                SecondaryButton("copy.again", systemImage: "doc.on.doc", action: onCopyAgain)
            }
            .padding(Tokens.Space.screenPadding)
            .background(Tokens.Colors.bg)
        }
        .background(Tokens.Colors.bg)
        .presentationDetents([.large])
        .accessibilityIdentifier("screen.S07")
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

private struct CopyGuidePreview: View {
    var body: some View {
        DemoDataBadge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Colors.bg)
            .sheet(isPresented: .constant(true)) {
                CopyGuideSheet(guide: CopyGuide(serviceName: "Zalo", body: "Chiều nay con về muộn nhé mẹ.",
                                                steps: ["Mở Zalo", "Chọn người nhận", "Dán tin nhắn", "Bấm Gửi"]),
                               onDone: {}, onCopyAgain: {})
            }
    }
}

#Preview("Light") { CopyGuidePreview() }
#Preview("Dark, AX5") { CopyGuidePreview().preferredColorScheme(.dark).dynamicTypeSize(.accessibility5) }
