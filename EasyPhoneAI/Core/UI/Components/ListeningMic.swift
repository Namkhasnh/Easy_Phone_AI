import SwiftUI

/// The big mic (UI_SCREENS §1.3, §2, §9, D-182): 120pt `primary` circle with `mic.fill`; listening → 140pt,
/// `stop.fill`, pulsing `honey` ring (+ 2pt `primary` outline in light mode, D-291). Reduce Motion → no pulse.
/// VoiceOver: label `home.mic.a11y`, value "Đang nghe" while listening, `.startsMediaSession`.
/// The visible caption ("Bấm để nói" / "Mình đang nghe…") belongs to the screen (S02 / S03).
struct ListeningMic: View {
    let isListening: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulse = false

    private var size: CGFloat { isListening ? Tokens.Size.micButtonListening : Tokens.Size.micButton }

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: Tokens.Size.iconHero * 0.75))   // icon inside the fixed-size circle
                .foregroundStyle(Tokens.Colors.onPrimary)
                .frame(width: size, height: size)
                .background(Tokens.Colors.primary, in: Circle())
                .background {
                    if isListening {
                        Circle()
                            .fill(Tokens.Colors.honey)
                            .overlay {
                                if colorScheme == .light {
                                    Circle().strokeBorder(Tokens.Colors.primary, lineWidth: Tokens.Size.borderIncreasedContrast)
                                }
                            }
                            .padding(-Tokens.Space.m)
                            .scaleEffect(pulse && !reduceMotion ? 1.08 : 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(Tokens.Space.l)                      // room for the ring
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isListening)
        .accessibilityLabel(Text("home.mic.a11y"))
        // TODO(spec): "Đang nghe" value has no key in UI_SCREENS §9 (DOC-24); `home.mic.listening.a11y` used.
        .accessibilityValue(isListening ? Text("home.mic.listening.a11y") : Text(verbatim: ""))
        .accessibilityAddTraits(.startsMediaSession)
        .onChange(of: isListening, initial: true) { _, listening in
            guard listening, !reduceMotion else { pulse = false; return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

#Preview("Light") {
    ListeningMicPreview()
}

#Preview("Dark") {
    ListeningMicPreview().preferredColorScheme(.dark)
}

private struct ListeningMicPreview: View {
    @State private var listening = false

    var body: some View {
        VStack(spacing: Tokens.Space.xl) {
            DemoDataBadge()
            ListeningMic(isListening: listening) { listening.toggle() }
            ListeningMic(isListening: true) {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Colors.bg)
    }
}
