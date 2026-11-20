import SwiftUI

/// Guide mascot **Khoai** (UI_SCREENS §2, P-41, D-289, D-327). Owner-supplied sprite frames (192×208 px PNG,
/// transparent), asset `mascot.<row>.<nn>` in `Assets.xcassets/Mascot`, plus a code motion layer (`MascotMotion`).
/// VoiceOver skips it, it has no text of its own and never signals a result on its own (D-102, D-124); touches only
/// play a reaction (D-327). Reduce Motion → one still frame, no motion (UI_SCREENS §9).
enum MascotPose: String, CaseIterable, Sendable {
    case greeting, listening, thinking, asking, happy, sorry

    /// UI_SCREENS §2 pose → sprite row (DOC-36): greeting = wave once, then idle.
    var clip: MascotClip {
        switch self {
        case .greeting: MascotClip(intro: MascotClip.waving, loop: MascotClip.idle)
        case .listening: MascotClip(intro: [], loop: MascotClip.idle)
        case .thinking: MascotClip(intro: [], loop: MascotClip.running)
        case .asking: MascotClip(intro: [], loop: MascotClip.waiting)
        case .happy: MascotClip(intro: [], loop: MascotClip.jumping)   // S04 later: only `succeeded` with evidence (P-41)
        case .sorry: MascotClip(intro: [], loop: MascotClip.failed)
        }
    }

    /// Owner 2026-11-20 ("vẫn giật", "mặt không tự nhiên"): the frames are separate paintings (the face changes
    /// every frame, the body drifts 2–9 px), so the puppet style keeps ONE face per pose and lets `MascotMotion`
    /// move it at 60 fps. Only the greeting wave keeps its frames (code cannot draw a waving paw), played once.
    var puppetClip: MascotClip {
        func still(_ name: String) -> [MascotFrame] { [MascotFrame(name: name, duration: .seconds(1))] }
        switch self {
        case .greeting: return MascotClip(intro: MascotClip.waving, loop: still("mascot.idle.00"))
        case .listening: return MascotClip(intro: [], loop: still("mascot.idle.00"))
        case .thinking: return MascotClip(intro: [], loop: still("mascot.running.00"))
        case .asking: return MascotClip(intro: [], loop: still("mascot.waiting.00"))
        case .happy: return MascotClip(intro: [], loop: still("mascot.waving.01"))
        case .sorry: return MascotClip(intro: [], loop: still("mascot.failed.03"))
        }
    }

    func clip(_ style: MascotStyle) -> MascotClip { style == .puppet ? puppetClip : clip }
}

/// D-327: `frames` = the owner's sprite rows (current screens); `puppet` = one face per pose + code motion.
enum MascotStyle: String, Sendable, CaseIterable {
    case frames, puppet
}

struct MascotFrame: Hashable, Sendable {
    let name: String
    let duration: Duration
}

/// Frames played once (`intro`), then `loop` forever.
struct MascotClip: Hashable, Sendable {
    let intro: [MascotFrame]
    let loop: [MascotFrame]

    var allFrames: [MascotFrame] { intro + loop }
    /// Shown first and under Reduce Motion.
    var stillFrame: MascotFrame { intro.first ?? loop[0] }

    /// What actually plays: Reduce Motion → only the still frame, nothing changes over time.
    func playlist(reduceMotion: Bool) -> (intro: [MascotFrame], loop: [MascotFrame]) {
        reduceMotion ? ([], [stillFrame]) : (intro, loop)
    }

    /// Frame times in ms, as in the owner's preview GIFs (`qa/previews/<row>.gif`).
    private static func row(_ name: String, _ ms: [Int]) -> [MascotFrame] {
        ms.enumerated().map { MascotFrame(name: "mascot.\(name).\(String(format: "%02d", $0.offset))",
                                          duration: .milliseconds($0.element)) }
    }

    static let idle = row("idle", [280, 110, 110, 140, 140, 320])
    static let waving = row("waving", [140, 140, 140, 280])
    static let jumping = row("jumping", [140, 140, 140, 140, 280])
    static let failed = row("failed", [140, 140, 140, 140, 140, 140, 140, 240])
    static let waiting = row("waiting", [150, 150, 150, 150, 150, 260])
    static let running = row("running", [120, 120, 120, 120, 120, 220])
}

struct MascotView: View {
    let pose: MascotPose
    var size: CGFloat = 96
    /// D-327: a one-shot touch reaction (tap → hop, pet → wiggle + hearts + light haptic).
    var reaction: MascotReactionEvent?
    /// D-327: voice loudness 0…1 while listening (bob).
    var level: Double = 0
    /// Debug preview only: behave as if Reduce Motion were on.
    var forceStill = false
    /// D-327: sprite rows (default, current screens) or one face + code motion.
    var style: MascotStyle = .frames

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var frame: String?
    @State private var reactionStart: Date?

    private var reduceMotion: Bool { systemReduceMotion || forceStill }
    private struct PlayKey: Hashable { let pose: MascotPose; let reduceMotion: Bool; let style: MascotStyle }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let now = context.date
            let elapsed = reactionStart.map { now.timeIntervalSince($0) } ?? -1
            let m = MascotMotion.transform(pose: pose, time: now.timeIntervalSinceReferenceDate, level: level,
                                           reaction: reaction?.kind, elapsed: elapsed, reduceMotion: reduceMotion)
            ZStack(alignment: .bottom) {
                // Depth without a backdrop (owner 2026-11-10): soft ground shadow under the paws + light drop shadow.
                Ellipse()
                    .fill(.black.opacity(0.22))
                    .frame(width: size * 0.62, height: size * 0.12)
                    .blur(radius: size * 0.04)
                    .scaleEffect(m.shadowScale)
                    .offset(y: size * 0.02)
                Image(frame ?? pose.clip(style).stillFrame.name)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(m.rotation), anchor: .bottom)
                    .offset(y: size * m.offsetY)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.05, x: 0, y: size * 0.04)
            }
            .overlay {
                if reaction?.kind == .pet, let hearts = MascotMotion.hearts(elapsed: elapsed, reduceMotion: reduceMotion) {
                    ForEach(hearts.indices, id: \.self) { i in
                        Image(systemName: "heart.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: size * 0.14, height: size * 0.14)   // decorative, sized to the mascot
                            .foregroundStyle(Tokens.Colors.danger)
                            .opacity(hearts[i].opacity)
                            .offset(x: size * hearts[i].x, y: size * hearts[i].y)
                    }
                }
            }
        }
        .frame(width: size, height: size)              // decorative, fixed-size slot (not text)
        .accessibilityHidden(true)
        .task(id: PlayKey(pose: pose, reduceMotion: reduceMotion, style: style)) { await play() }
        .onChange(of: reaction) { _, event in reactionStart = event == nil ? nil : .now }
        .sensoryFeedback(.impact(weight: .light), trigger: reaction) { _, new in new?.kind == .pet }
    }

    /// Cancelled automatically when the view disappears or the pose changes.
    private func play() async {
        let clip = pose.clip(style)
        let (intro, loop) = clip.playlist(reduceMotion: reduceMotion)
        frame = clip.stillFrame.name
        for f in intro {
            frame = f.name
            guard (try? await Task.sleep(for: f.duration)) != nil else { return }
        }
        guard loop.count > 1 else { frame = loop.first?.name ?? frame; return }
        while !Task.isCancelled {
            for f in loop {
                frame = f.name
                guard (try? await Task.sleep(for: f.duration)) != nil else { return }
            }
        }
    }
}

// MARK: - Previews (owner art, "Dữ liệu mẫu" not needed: no data shown)

#Preview("All poses") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))]) {
            ForEach(MascotPose.allCases, id: \.self) { pose in
                VStack {
                    MascotView(pose: pose, size: 96)
                    Text(verbatim: pose.rawValue).font(.caption)    // preview label only, not shipped UI
                }
            }
        }
        .padding()
    }
    .background(Tokens.Colors.bg)
}

#Preview("Greeting on honey, dark") {
    MascotView(pose: .greeting, size: 88)
        .frame(width: 96, height: 96)
        .background(Tokens.Colors.honey, in: Circle())
        .padding()
        .background(Tokens.Colors.bg)
        .preferredColorScheme(.dark)
}
