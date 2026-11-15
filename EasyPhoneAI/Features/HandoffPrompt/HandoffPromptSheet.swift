import SwiftUI

/// S08 Hand-off return prompt (UI_SCREENS S08, D-242): medium detent · icon · question · step summary ·
/// Primary "Đã xong" · Secondary "Chưa". Works by taps alone (UI_SCREENS §11).
struct HandoffPromptSheet: View {
    let prompt: HandoffPrompt
    let onDone: () -> Void
    let onNotYet: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.l) {
                Image(systemName: prompt.symbol)
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.primary)
                    .accessibilityHidden(true)
                Text(verbatim: prompt.question.text)
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: prompt.summary)                                 // user data (step summary)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Tokens.Space.m) {
                PrimaryButton("common.yesDone", action: onDone)
                SecondaryButton("common.notYet", action: onNotYet)
            }
            .padding(Tokens.Space.screenPadding)
            .background(Tokens.Colors.bg)
        }
        .background(Tokens.Colors.bg)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("screen.S08")
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            VStack {
                DemoDataBadge()
                HandoffPromptSheet(prompt: HandoffPrompt(draftId: UUID(), stepId: UUID(), symbol: "phone",
                                                         question: UserMessage(key: "handoff.call"),
                                                         summary: "Gọi điện: anh Minh"),
                                   onDone: {}, onNotYet: {})
            }
        }
}
