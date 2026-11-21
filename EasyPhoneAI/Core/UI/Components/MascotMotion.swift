import CoreGraphics
import Foundation

/// A touch on Khoai (D-327). Never starts a task: callers only show a tip / a reply (catalog keys).
enum MascotReaction: Sendable, Equatable {
    case tap, pet

    /// How long the one-shot reaction plays, in seconds.
    var duration: Double {
        switch self {
        case .tap: 0.7
        case .pet: 1.2
        }
    }
}

/// One reaction request; a new `id` replays the same kind (two taps in a row).
struct MascotReactionEvent: Sendable, Equatable {
    let kind: MascotReaction
    let id: Int
}

/// What the code motion does to the sprite at one moment (D-327). Offsets are fractions of the mascot size
/// (negative `offsetY` = up), rotation in degrees.
struct MascotTransform: Sendable, Equatable {
    var scaleX: Double = 1
    var scaleY: Double = 1
    var rotation: Double = 0
    var offsetY: Double = 0
    var shadowScale: Double = 1

    static let identity = MascotTransform()
}

/// Code motion on top of the sprite frames (UI_SCREENS §2, D-327). Pure: the view asks for the transform at a time,
/// tests check the numbers. Reduce Motion → `identity` always (UI_SCREENS §9).
enum MascotMotion {
    static let breatheAmount = 0.02
    static let breathePeriod = 2.4
    static let tiltDegrees = 6.0
    static let hopHeight = 0.12
    static let tapHopHeight = 0.18

    static func clamped(_ level: Double) -> Double { min(max(level.isFinite ? level : 0, 0), 1) }

    /// The transform at `time` seconds for `pose`; `level` = voice loudness 0…1 (listening only);
    /// `reaction` + `elapsed` = a running one-shot touch reaction.
    static func transform(pose: MascotPose, time t: Double, level: Double = 0,
                          reaction: MascotReaction? = nil, elapsed: Double = 0,
                          reduceMotion: Bool, rig: Bool = false) -> MascotTransform {
        guard !reduceMotion else { return .identity }
        if rig {
            // The rig turns the head / ears / tail itself, so the whole body only breathes, bobs and hops.
            var m = transform(pose: pose, time: t, level: level, reaction: reaction == .pet ? nil : reaction,
                              elapsed: elapsed, reduceMotion: false)
            m.rotation = 0
            return m
        }
        var m = MascotTransform()
        // Every pose breathes: a little taller, a little narrower.
        let breath = breatheAmount * (0.5 - 0.5 * cos(2 * .pi * t / breathePeriod))
        m.scaleY += breath
        m.scaleX -= breath * 0.4

        switch pose {
        case .greeting:
            break
        case .listening:
            let l = clamped(level)
            let bob = abs(sin(2 * .pi * t / 0.45))
            m.offsetY -= 0.04 * l * bob
            m.scaleY += 0.03 * l * bob
        case .thinking:
            m.offsetY -= 0.02 * abs(sin(2 * .pi * t / 0.24))
        case .asking:
            // Tilt to one side, hold, come back: a sine pushed past ±1 and clipped.
            m.rotation += tiltDegrees * min(max(1.6 * sin(2 * .pi * t / 3.2), -1), 1)
        case .happy:
            apply(hop(phase: (t / 0.9).truncatingRemainder(dividingBy: 1), height: hopHeight), to: &m)
        case .sorry:
            m.rotation += 2.5 * sin(2 * .pi * t / 1.6)
            m.scaleY -= 0.01
        }

        if let reaction, elapsed >= 0, elapsed < reaction.duration {
            let p = elapsed / reaction.duration
            switch reaction {
            case .tap:
                apply(hop(phase: p, height: tapHopHeight), to: &m)
            case .pet:
                m.rotation += 4 * sin(2 * .pi * elapsed / 0.3) * (1 - p)
                m.scaleY -= 0.03 * (1 - p)
                m.scaleX += 0.02 * (1 - p)
            }
        }
        return m
    }

    /// One hop over `phase` 0…1: in the air for the first 70 %, then a squash on landing.
    static func hop(phase p: Double, height: Double) -> MascotTransform {
        var m = MascotTransform.identity
        let air = 0.7
        if p < air {
            let h = sin(.pi * p / air)
            m.offsetY = -height * h
            m.shadowScale = 1 - 0.4 * h
            m.scaleY = 1 + 0.02 * h                      // light stretch: a bigger one distorts the face (owner)
            m.scaleX = 1 - 0.015 * h
        } else {
            let q = sin(.pi * (p - air) / (1 - air))
            m.scaleY = 1 - 0.04 * q                      // light squash on landing
            m.scaleX = 1 + 0.03 * q
        }
        return m
    }

    private static func apply(_ h: MascotTransform, to m: inout MascotTransform) {
        m.offsetY += h.offsetY
        m.scaleY *= h.scaleY
        m.scaleX *= h.scaleX
        m.shadowScale *= h.shadowScale
    }

    /// Hearts after a pet (D-327): three, rising and fading over the reaction. `nil` = not shown.
    static func hearts(elapsed: Double, reduceMotion: Bool) -> [(x: Double, y: Double, opacity: Double)]? {
        let d = MascotReaction.pet.duration
        guard !reduceMotion, elapsed >= 0, elapsed < d else { return nil }
        return [(-0.28, 0.0), (0.0, 0.15), (0.26, 0.05)].map { x, delay in
            let p = min(max((elapsed / d - delay) / (1 - delay), 0), 1)
            return (x: x, y: -0.2 - 0.35 * p, opacity: p == 0 ? 0 : 1 - p)
        }
    }
}

/// Angles (degrees, + = clockwise) of the cut-out rig parts (D-327, owner 2026-11-21 "làm cách cắt ghép").
/// Ears: + on the left ear / − on the right ear lifts it (perk), the opposite droops it. Tail: − lifts, + droops.
struct MascotRigAngles: Sendable, Equatable {
    var head: Double = 0
    var earL: Double = 0
    var earR: Double = 0
    var tail: Double = 0

    static let rest = MascotRigAngles()
}

/// Where each rig part turns, as unit points of the shared layer canvas (from `tools/khoai_rig/cut.py`).
enum MascotRig {
    static let headPivot = (x: 0.3582, y: 0.5485)
    static let earLPivot = (x: 0.2687, y: 0.0633)
    static let earRPivot = (x: 0.5174, y: 0.1350)
    static let tailPivot = (x: 0.7711, y: 0.8523)
    static let maxHead = 7.0, maxEar = 9.0, maxTail = 16.0

    /// The rig angles at `time` for `pose` (same inputs as `MascotMotion.transform`). Reduce Motion → `rest`.
    static func angles(pose: MascotPose, time t: Double, level: Double = 0,
                       reaction: MascotReaction? = nil, elapsed: Double = 0,
                       reduceMotion: Bool) -> MascotRigAngles {
        guard !reduceMotion else { return .rest }
        func wave(_ period: Double, _ phase: Double = 0) -> Double { sin(2 * .pi * t / period + phase) }
        var a = MascotRigAngles()
        // Alive at rest: slow head sway, ears drift, a lazy tail wag and a quick right-ear flick every 5 s.
        a.head = 1.2 * wave(4.8)
        a.earL = 1.5 * wave(3.1)
        a.earR = -1.5 * wave(3.4, 1) - 5 * flick(t.truncatingRemainder(dividingBy: 5) - 3.6)
        a.tail = 4 * wave(1.4)

        switch pose {
        case .greeting:
            a.tail = 10 * wave(0.5)
            a.head += 3
        case .listening:
            let l = MascotMotion.clamped(level)
            a.earL += 4 + 2 * l
            a.earR -= 4 + 2 * l
            a.head += 2.5
            a.tail = (4 + 6 * l) * wave(0.7)
        case .thinking:
            a.head += 4 * min(max(1.4 * wave(4.0), -1), 1)
            a.tail = 2 * wave(2.2)
        case .asking:
            // The dog head tilt: tilt, hold, come back (clipped sine), the ear on the high side lifts.
            let tilt = min(max(1.6 * wave(3.2), -1), 1)
            a.head = 6 * tilt
            a.earL += 3 * max(tilt, 0)
            a.earR -= 3 * max(-tilt, 0)
        case .happy:
            a.tail = 14 * wave(0.36)
            let hop = (t / 0.9).truncatingRemainder(dividingBy: 1)
            a.earL += 5 * sin(2 * .pi * hop)
            a.earR -= 5 * sin(2 * .pi * hop)
        case .sorry:
            a.head = -3 + 0.8 * wave(3.0)
            a.earL = -5
            a.earR = 5
            a.tail = 9 + 1.5 * wave(2.0)
        }

        if let reaction, elapsed >= 0, elapsed < reaction.duration {
            let p = elapsed / reaction.duration, fade = 1 - p
            switch reaction {
            case .tap:
                a.earL += 7 * sin(.pi * p)
                a.earR -= 7 * sin(.pi * p)
                a.tail += 8 * sin(2 * .pi * elapsed / 0.3) * fade
            case .pet:
                a.head += 4 * sin(2 * .pi * elapsed / 0.4) * fade
                a.earL -= 4 * sin(.pi * p)                     // ears fold back, eyes stay the same
                a.earR += 4 * sin(.pi * p)
                a.tail += 12 * sin(2 * .pi * elapsed / 0.28) * fade
            }
        }
        a.head = min(max(a.head, -maxHead), maxHead)
        a.earL = min(max(a.earL, -maxEar), maxEar)
        a.earR = min(max(a.earR, -maxEar), maxEar)
        a.tail = min(max(a.tail, -maxTail), maxTail)
        return a
    }

    /// A 0.35 s up-and-back pulse starting at `s` = 0 (0 outside).
    static func flick(_ s: Double) -> Double {
        guard s > 0, s < 0.35 else { return 0 }
        return sin(.pi * s / 0.35)
    }
}

/// Khoai's own lines (D-327, UI_SCREENS §10.5): catalog keys only, never LLM text (D-220).
enum KhoaiLines {
    static let tips = (1...5).map { "khoai.tip.\($0)" }
    static let petReply = "khoai.pet.reply"

    /// The tip after `index` (rotating), so each tap shows the next one.
    static func tip(after index: Int?) -> (index: Int, key: String) {
        let next = ((index ?? -1) + 1) % tips.count
        return (next, tips[next])
    }
}
