import SwiftUI

/// Row of one draft (S14 History, S02 "Việc chưa xong"): kind icon + summary + relative time + `StateBadge`
/// (+ "{done}/{total} bước"), chevron, ≥ 72pt (UI_SCREENS S14).
struct DraftRowView: View {
    let row: DraftRow

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: row.symbol)
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.primary)
                .frame(width: Tokens.Size.iconRow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: row.summary)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text(verbatim: row.time)
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                StateBadge(state: row.badgeState, args: row.badgeArgs)
                if let steps = row.stepsText {
                    Text(verbatim: steps)
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(Tokens.Fonts.label)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Tokens.Space.s)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        DemoDataBadge()
        DraftRowView(row: DraftRow(id: UUID(), symbol: "message", summary: "Soạn tin nhắn: anh Minh",
                                   time: "Hôm nay 14:05", badgeState: .awaitingApproval, badgeArgs: [], stepsText: nil))
    }
    .padding(Tokens.Space.screenPadding)
    .background(Tokens.Colors.bg)
}
