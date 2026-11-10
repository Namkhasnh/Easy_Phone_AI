import Foundation
import Testing
import UIKit
@testable import EasyPhoneAI

/// 1B.16 — Khoai mascot (UI_SCREENS §2, S02, S03, §9; P-41, D-289; DOC-36 sprite frames).
@MainActor
@Suite("Mascot Khoai (D-289)")
struct MascotTests {
    @Test(arguments: MascotPose.allCases)
    func everyFrameIsBundledWithATime(pose: MascotPose) throws {
        let clip = pose.clip
        #expect(!clip.loop.isEmpty)
        for frame in clip.allFrames {
            let image = try #require(UIImage(named: frame.name), "missing asset \(frame.name)")
            #expect(image.size.width > 0)
            #expect(frame.duration > .zero)
        }
    }

    @Test func poseToSpriteRow() {
        #expect(MascotPose.greeting.clip.intro.map(\.name).first == "mascot.waving.00")
        #expect(MascotPose.greeting.clip.loop == MascotClip.idle)
        #expect(MascotPose.listening.clip.loop == MascotClip.idle)
        #expect(MascotPose.thinking.clip.loop == MascotClip.running)
        #expect(MascotPose.asking.clip.loop == MascotClip.waiting)
        #expect(MascotPose.sorry.clip.loop == MascotClip.failed)
        #expect(MascotPose.happy.clip.loop == MascotClip.jumping)
        #expect(MascotClip.idle.map(\.duration) == [280, 110, 110, 140, 140, 320].map { .milliseconds($0) })
    }

    @Test(arguments: MascotPose.allCases)
    func reduceMotionShowsOneStillFrame(pose: MascotPose) {
        let still = pose.clip.playlist(reduceMotion: true)
        #expect(still.intro.isEmpty && still.loop == [pose.clip.stillFrame])
        let moving = pose.clip.playlist(reduceMotion: false)
        #expect(moving.intro.count + moving.loop.count > 1)
    }

    // MARK: - S03 pose follows the mode

    func conversation(_ text: String = "Nhắc tôi uống thuốc", pet: Bool = true) -> ConversationViewModel {
        let repo = MockTaskRepository()
        let local = MockLocalDataRepository()
        local.settings().petEnabled = pet
        let draft = TaskDraft(inputMode: .voice, originalInput: text)
        repo.save(draft)
        return ConversationViewModel(draftId: draft.id, repository: repo, speech: MockSpeechService(),
                                     api: MockAPIClient(), tts: MockTTSService(), localData: local)
    }

    @Test func conversationPoseFollowsMode() {
        let vm = conversation()
        #expect(vm.mascotPose == .listening)                             // transcript
        vm.showWorking()
        #expect(vm.mascotPose == .thinking)
        vm.showFollowUp(.init(question: "Bạn muốn được nhắc lúc mấy giờ?"))
        #expect(vm.mascotPose == .asking)
        vm.showUnsupported(.init(reason: "recurringEvent", message: nil))
        #expect(vm.mascotPose == .sorry)
        vm.rephrase()
        #expect(vm.mascotPose == .listening)
        vm.showParseFailed()
        #expect(vm.mascotPose == .sorry)                                 // notice shown
    }

    @Test func petToggleHidesKhoai() {
        #expect(conversation(pet: true).showsMascot)
        #expect(!conversation(pet: false).showsMascot)                   // settings.pet off (D-289)
    }
}
