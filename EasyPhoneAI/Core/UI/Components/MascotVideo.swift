import AVFoundation
import CoreImage
import SwiftUI

/// D-327 (owner 2026-11-22): Khoai clips made with an AI image-to-video tool from the owner's smiling Khoai picture
/// (start = end frame, so every clip loops and joins the others on the same pose), background removed on the Mac
/// (`tools/khoai_rig/make_clip.sh`), stored as HEVC-with-alpha `.mov` in `Resources/KhoaiVideo`.
/// Played in pure SwiftUI (D-014): an `AVPlayerItemVideoOutput` hands one frame per display tick to an `Image`.
enum MascotVideoClip {
    static let idle = "khoai_tho"

    /// What plays for a pose: clips played once, then the last one loops. Missing files are skipped;
    /// an empty list = no clip at all (the view falls back to the rig).
    static func playlist(for pose: MascotPose, reaction: MascotReaction? = nil) -> [String] {
        let loop = switch pose {
        case .greeting: idle
        case .listening: "khoai_dang_nghe"
        case .thinking: "khoai_dang_xu_ly"
        case .asking: "khoai_hoi_them"
        case .happy: "khoai_mung"
        case .sorry: "khoai_buon"
        }
        var list: [String] = []
        switch reaction {
        case .tap: list.append("khoai_cham")
        case .pet: list.append("khoai_xoa_dau")
        case nil: if pose == .greeting { list.append("khoai_chao") }   // wave hello once, then breathe
        }
        list.append(url(loop) == nil ? idle : loop)
        return list.filter { url($0) != nil }
    }

    /// The loop clip for a pose, `nil` if none is bundled.
    static func name(for pose: MascotPose) -> String? { playlist(for: pose).last }

    static func url(_ file: String) -> URL? { Bundle.main.url(forResource: file, withExtension: "mov") }

    /// First frame of every clip (all start on the same picture); also the Reduce Motion still.
    static let still = "mascot.video.still"

    /// S03 listening (owner 2026-11-22): Khoai clinging to a round honey window, ring drawn into the clip
    /// (`tools/khoai_rig/window.py`), square; its Reduce Motion still.
    static let listeningWindow = "khoai_nghe_cua_so"
    static let listeningWindowStill = "mascot.window.still"
}

/// Plays `files` in order, each once, then loops the last one. Muted. Main actor only (read by `TimelineView`).
@MainActor
final class MascotVideoPlayer {
    private let player = AVPlayer()
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    private let files: [String]
    private var index = 0
    private var image: CGImage?
    private var endObserver: NSObjectProtocol?
    private static let context = CIContext()

    init(files: [String]) {
        self.files = files
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: nil, queue: .main) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated { self?.itemEnded(item) }
        }
        load(0)
    }

    isolated deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    private func load(_ i: Int) {
        guard files.indices.contains(i), let url = MascotVideoClip.url(files[i]) else { return }
        index = i
        player.currentItem?.remove(output)
        let item = AVPlayerItem(url: url)
        item.add(output)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func itemEnded(_ item: AVPlayerItem?) {
        guard let item, item === player.currentItem else { return }
        if index < files.count - 1 {
            load(index + 1)                              // every clip ends on the first frame: a seamless join
        } else {
            player.seek(to: .zero)
            player.play()
        }
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

/// One playlist drawn as an `Image` each display tick. Decorative (VoiceOver skips the mascot).
struct MascotVideoView: View {
    let files: [String]
    var still = MascotVideoClip.still
    @State private var player: MascotVideoPlayer?

    var body: some View {
        TimelineView(.animation) { _ in
            if let frame = player?.frame() {
                Image(decorative: frame, scale: 1).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(still).resizable().interpolation(.high).scaledToFit()
            }
        }
        .onAppear { player = MascotVideoPlayer(files: files) }
        .onDisappear { player?.stop(); player = nil }
    }
}
