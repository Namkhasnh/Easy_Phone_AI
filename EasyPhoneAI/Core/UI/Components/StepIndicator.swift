import SwiftUI

/// "Bước {n}/{total}" + dots (UI_SCREENS §2). Dots are decorative (`accessibilityHidden`).
/// `current` is 1-based.
struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            // TODO(spec): key `stepIndicator.label` is not named in UI_SCREENS §2 (DOC-23).
            Text(verbatim: UserMessage(key: "stepIndicator.label", args: ["\(current)", "\(total)"]).text)
                .font(Tokens.Fonts.label)
                .foregroundStyle(Tokens.Colors.textSecondary)
            HStack(spacing: Tokens.Space.s) {
                ForEach(1...max(total, 1), id: \.self) { i in
                    Circle()
                        .fill(i <= current ? Tokens.Colors.primary : Tokens.Colors.border)
                        .frame(width: Tokens.Space.s, height: Tokens.Space.s)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Tokens.Space.l) {
        StepIndicator(current: 1, total: 2)
        StepIndicator(current: 2, total: 3)
    }
    .padding(Tokens.Space.screenPadding)
    .background(Tokens.Colors.bg)
}
