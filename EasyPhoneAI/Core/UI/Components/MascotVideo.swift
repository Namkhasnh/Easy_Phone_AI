import AVFoundation
import CoreImage
import SwiftUI

/// D-327 (owner 2026-11-22): Khoai clips made with an AI image-to-video tool from the owner's Khoai picture (start =
/// end frame, so every clip loops and joins the others on the same pose), background removed on the Mac
/// (`tools/khoai_rig/matte.swift`, `clean.py`), stored as HEVC-with-alpha `.mov` in `Resources/KhoaiVideo`.
/// Played in pure SwiftUI (D-014): an `AVPlayerItemVideoOutput` hands one frame per display tick to an `Image`.
enum MascotVideoClip {
    /// The clip file for a pose, `nil` while the owner has not made it yet (the view falls back to the rig).
    static func name(for pose: MascotPose) -> String? {
        let file = switch pose {
        case .greeting: "khoai_chao"
        case .listening: "khoai_dang_nghe"
        case .thinking: "khoai_dang_xu_ly"
        case .asking: "khoai_hoi_them"
        case .happy: "khoai_mung"
        case .sorry: "khoai_buon"
        }
        return url(file) == nil ? nil : file
    }

    static func url(_ file: String) -> URL? { Bundle.main.url(forResource: file, withExtension: "mov") }

    /// First frame of every clip (all start on the same picture); also the Reduce Motion still.
    static let still = "mascot.video.still"
}

/// One looping, muted clip. Main actor only: created and read by the view's `TimelineView`.
@MainActor
final class MascotVideoPlayer {
    private let player = AVPlayer()
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    private var image: CGImage?
    private var endObserver: NSObjectProtocol?
    private static let context = CIContext()

    init(file: String) {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        guard let url = MascotVideoClip.url(file) else { return }
        let item = AVPlayerItem(url: url)
        item.add(output)
        player.replaceCurrentItem(with: item)
        // Every clip ends on its first frame, so jumping back to the start is seamless.
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [player] _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
    }

    isolated deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func stop() { player.pause() }

    /// The frame to show now; keeps the last one between new video frames.
    func frame() -> CGImage? {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: time),
           let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
            let ci = CIImage(cvPixelBuffer: buffer)
            image = Self.context.createCGImage(ci, from: ci.extent)
        }
        return image
    }
}

/// The clip for one pose, drawn as an `Image` each display tick. Decorative (VoiceOver skips the mascot).
struct MascotVideoView: View {
    let file: String
    @State private var player: MascotVideoPlayer?

    var body: some View {
        TimelineView(.animation) { _ in
            if let frame = player?.frame() {
                Image(decorative: frame, scale: 1).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(MascotVideoClip.still).resizable().interpolation(.high).scaledToFit()
            }
        }
        .onAppear { player = MascotVideoPlayer(file: file) }
        .onDisappear { player?.stop(); player = nil }
    }
}
