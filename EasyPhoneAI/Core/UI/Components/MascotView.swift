import SwiftUI

/// Guide mascot **Khoai** (UI_SCREENS §2, P-41, D-289). Owner-supplied sprite frames (192×208 px PNG, transparent),
/// asset `mascot.<row>.<nn>` in `Assets.xcassets/Mascot`. Decorative only: VoiceOver skips it, no tap action, no text,
/// never signals a result on its own (D-102, D-124). Reduce Motion → one still frame (UI_SCREENS §9).
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: String?

    private struct PlayKey: Hashable { let pose: MascotPose; let reduceMotion: Bool }

    var body: some View {
        Image(frame ?? pose.clip.stillFrame.name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            // Depth without a backdrop (owner 2026-11-10): soft ground shadow under the paws + light drop shadow.
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(.black.opacity(0.22))
                    .frame(width: size * 0.62, height: size * 0.12)
                    .blur(radius: size * 0.04)
                    .offset(y: size * 0.02)
            }
            .shadow(color: .black.opacity(0.18), radius: size * 0.05, x: 0, y: size * 0.04)
            .frame(width: size, height: size)              // decorative, fixed-size slot (not text)
            .accessibilityHidden(true)
            .task(id: PlayKey(pose: pose, reduceMotion: reduceMotion)) { await play() }
    }

    /// Cancelled automatically when the view disappears or the pose changes.
    private func play() async {
        let (intro, loop) = pose.clip.playlist(reduceMotion: reduceMotion)
        frame = pose.clip.stillFrame.name
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
