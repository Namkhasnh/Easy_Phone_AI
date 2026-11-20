import Foundation
import Testing
import UIKit
@testable import EasyPhoneAI

/// 1G.K2 — Khoai motion layer (UI_SCREENS §2, §10.5; D-327).
@Suite("Mascot motion (D-327)")
struct MascotMotionTests {
    static let times: [Double] = stride(from: 0.0, through: 6.4, by: 0.05).map { $0 }

    @Test(arguments: MascotPose.allCases)
    func reduceMotionIsAlwaysStill(pose: MascotPose) {
        for t in Self.times {
            #expect(MascotMotion.transform(pose: pose, time: t, level: 1, reaction: .tap, elapsed: 0.3,
                                           reduceMotion: true) == .identity)
        }
        #expect(MascotMotion.hearts(elapsed: 0.3, reduceMotion: true) == nil)
    }

    @Test(arguments: MascotPose.allCases)
    func everyPoseBreathesGently(pose: MascotPose) {
        let peak = MascotMotion.transform(pose: .greeting, time: MascotMotion.breathePeriod / 2, reduceMotion: false)
        #expect(abs(peak.scaleY - 1.02) < 0.0001)
        for t in Self.times {
            let m = MascotMotion.transform(pose: pose, time: t, level: 1, reduceMotion: false)
            #expect(m.scaleY > 0.9 && m.scaleY < 1.1)                 // never distorts the art
            #expect(abs(m.rotation) <= MascotMotion.tiltDegrees + 0.001)
            #expect(m.offsetY <= 0.0001 && m.offsetY >= -0.2)         // only moves up, never sinks
        }
    }

    @Test func askingTiltsAndHolds() {
        let rotations = Self.times.map { MascotMotion.transform(pose: .asking, time: $0, reduceMotion: false).rotation }
        let tilt = MascotMotion.tiltDegrees - 0.1
        #expect(rotations.max()! > tilt)
        #expect(rotations.min()! < -tilt)
        #expect(rotations.filter { abs($0) > tilt }.count > 10)          // holds the tilt a moment
    }

    @Test func happyHopsWithSquashAndShadow() {
        let up = MascotMotion.hop(phase: 0.35, height: MascotMotion.hopHeight)
        #expect(abs(up.offsetY + MascotMotion.hopHeight) < 0.0001)       // top of the hop
        #expect(up.shadowScale < 0.7)                                    // shadow shrinks in the air
        let land = MascotMotion.hop(phase: 0.85, height: MascotMotion.hopHeight)
        #expect(land.offsetY == 0 && land.scaleY < 0.97 && land.scaleX > 1.02)
        #expect(land.scaleY > 0.95)                                      // never squashes the face hard
        #expect(MascotMotion.hop(phase: 0, height: 0.2) == .identity)
    }

    @Test func listeningBobFollowsTheVoiceLevel() {
        let t = 0.45 / 4                                                 // bob peak
        let quiet = MascotMotion.transform(pose: .listening, time: t, level: 0, reduceMotion: false)
        let loud = MascotMotion.transform(pose: .listening, time: t, level: 1, reduceMotion: false)
        let tooLoud = MascotMotion.transform(pose: .listening, time: t, level: 7, reduceMotion: false)
        #expect(quiet.offsetY == 0)
        #expect(loud.offsetY < -0.03)
        #expect(tooLoud == loud)                                         // clamped to 0…1
        #expect(MascotMotion.clamped(.nan) == 0 && MascotMotion.clamped(-1) == 0)
    }

    @Test func reactionsPlayOnceThenStop() {
        let mid = MascotMotion.transform(pose: .greeting, time: 0, reaction: .tap, elapsed: 0.245, reduceMotion: false)
        #expect(mid.offsetY < -0.15)
        let after = MascotMotion.transform(pose: .greeting, time: 0, reaction: .tap, elapsed: 0.8, reduceMotion: false)
        #expect(after == MascotMotion.transform(pose: .greeting, time: 0, reduceMotion: false))
        let pet = MascotMotion.transform(pose: .greeting, time: 0, reaction: .pet, elapsed: 0.075, reduceMotion: false)
        #expect(pet.rotation > 3)
        #expect(MascotMotion.hearts(elapsed: 0.6, reduceMotion: false)?.count == 3)
        #expect(MascotMotion.hearts(elapsed: 1.3, reduceMotion: false) == nil)
    }

    @Test(arguments: MascotPose.allCases)
    func puppetKeepsOneFacePerPose(pose: MascotPose) throws {
        let clip = pose.clip(.puppet)
        #expect(clip.loop.count == 1)                                    // no face changes while looping
        #expect(clip.intro.isEmpty == (pose != .greeting))               // only the wave plays its frames, once
        _ = try #require(UIImage(named: clip.loop[0].name))
        #expect(pose.clip(.frames) == pose.clip)
    }

    @Test func tipsRotateThroughCatalogKeys() throws {
        var index: Int?
        var seen: [String] = []
        for _ in 0..<6 {
            let next = KhoaiLines.tip(after: index)
            index = next.index
            seen.append(next.key)
        }
        #expect(seen == KhoaiLines.tips + [KhoaiLines.tips[0]])

        let keys = try StringScanTests.keys("EasyPhoneAI/Resources/Localizable.xcstrings")
        let mine = KhoaiLines.tips + [KhoaiLines.petReply, "settings.khoaiPlayground", "dev.khoai.title",
                                      "dev.khoai.hint", "dev.khoai.tap", "dev.khoai.pet", "dev.khoai.level",
                                      "dev.khoai.forceStill", "dev.khoai.puppet"] + MascotPose.allCases.map { "dev.khoai.pose." + $0.rawValue }
        for key in mine { #expect(keys.contains(key), "missing \(key)") }
    }
}
