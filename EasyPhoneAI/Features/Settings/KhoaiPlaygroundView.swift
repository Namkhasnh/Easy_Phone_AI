#if DEBUG
import SwiftUI

/// D-327 step 1: a Debug-only screen (S15 › Nâng cao › "Xem thử Khoai") to try Khoai's motion layer before it goes
/// into S02 / S03. Touches only play a reaction and show a catalog line; nothing is created or sent (D-327).
struct KhoaiPlaygroundView: View {
    @State private var pose: MascotPose = .greeting
    @State private var level = 0.5
    @State private var forceStill = false
    @State private var style: MascotStyle = .video
    @State private var reaction: MascotReactionEvent?
    @State private var tipIndex: Int?
    @State private var lineKey = "dev.khoai.hint"

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.l) {
                Text(LocalizedStringKey(lineKey))
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.onHoney)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.m)
                    .background(Tokens.Colors.honey, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))

                MascotView(pose: pose, size: 176, reaction: reaction, level: level, forceStill: forceStill,
                           style: style)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: tap)
                    .gesture(DragGesture(minimumDistance: 12).onEnded { _ in pet() })

                HStack(spacing: Tokens.Space.m) {
                    SecondaryButton("dev.khoai.tap", systemImage: "hand.point.up.left", action: tap)
                    SecondaryButton("dev.khoai.pet", systemImage: "hand.wave", action: pet)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Tokens.Space.s) {
                    ForEach(MascotPose.allCases, id: \.self) { p in
                        Button { pose = p } label: {
                            Label {
                                Text(LocalizedStringKey("dev.khoai.pose." + p.rawValue))
                            } icon: {
                                Image(systemName: pose == p ? "checkmark.circle.fill" : "circle")
                            }
                            .font(Tokens.Fonts.label)
                            .foregroundStyle(Tokens.Colors.primary)
                            .frame(maxWidth: .infinity, minHeight: Tokens.Size.tapTargetMin, alignment: .leading)
                            .padding(.horizontal, Tokens.Space.m)
                            .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.button))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("dev.khoai.level")
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Slider(value: $level, in: 0...1)
                        .tint(Tokens.Colors.primary)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("dev.khoai.style")
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Picker(selection: $style) {
                        ForEach(MascotStyle.allCases, id: \.self) { s in
                            Text(LocalizedStringKey("dev.khoai.style." + s.rawValue)).tag(s)
                        }
                    } label: {
                        Text("dev.khoai.style")
                    }
                    .pickerStyle(.segmented)
                }
                Toggle(isOn: $forceStill) {
                    Text("dev.khoai.forceStill")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                }
                .frame(minHeight: Tokens.Size.buttonMinHeight)
            }
            .padding(Tokens.Space.screenPadding)
        }
        .background(Tokens.Colors.bg)
        .navigationTitle(Text("dev.khoai.title"))
        .accessibilityIdentifier("screen.khoaiPlayground")
    }

    /// Tap → hop + the next tip (D-327).
    private func tap() {
        let next = KhoaiLines.tip(after: tipIndex)
        tipIndex = next.index
        lineKey = next.key
        reaction = MascotReactionEvent(kind: .tap, id: (reaction?.id ?? 0) + 1)
    }

    /// Pet → wiggle + hearts + light haptic + reply (D-327).
    private func pet() {
        lineKey = KhoaiLines.petReply
        reaction = MascotReactionEvent(kind: .pet, id: (reaction?.id ?? 0) + 1)
    }
}

#Preview {
    NavigationStack { KhoaiPlaygroundView() }
}
#endif
