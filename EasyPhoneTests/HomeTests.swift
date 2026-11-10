import Foundation
import Testing
@testable import EasyPhoneAI

/// 1B.1 — UI_SCREENS S02, spec §6.10 AC5, D-244, P-36, P-40, D-289.
@MainActor
@Suite("Home (UI_SCREENS S02)")
struct HomeTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-10T15:00:00+07:00")!

    let repo = MockTaskRepository()
    let local = MockLocalDataRepository()

    @discardableResult
    func add(_ state: TaskState, title: String, at: String, archived: Bool = false) -> TaskDraft {
        let step = TaskStep(order: 0, kind: .reminder, operation: .create, state: state,
                            fields: [Field(id: "title", type: .text, value: title)])
        let d = TaskDraft(inputMode: .text, originalInput: "x", steps: [step], isArchived: archived)
        repo.save(d)
        d.updatedAt = Validator.parseDateTime(at)!
        return d
    }

    func model() -> HomeViewModel {
        let vm = HomeViewModel(repository: repo, localData: local, now: { Self.now }, timeZone: Self.tz)
        vm.load()
        return vm
    }

    @Test func unfinishedListsNeedsYouAndWaitingNewestFirstMaxThree() {
        add(.awaitingApproval, title: "A", at: "2026-11-10T09:00:00+07:00")
        add(.handedOff, title: "B", at: "2026-11-10T14:00:00+07:00")        // waiting
        add(.failed, title: "C", at: "2026-11-10T12:00:00+07:00")           // failed is not closed (D-244)
        add(.needsInfo, title: "D", at: "2026-11-08T12:00:00+07:00")        // 4th → cut
        add(.succeeded, title: "E", at: "2026-11-10T14:30:00+07:00")        // closed → never listed
        add(.cancelled, title: "F", at: "2026-11-10T14:40:00+07:00")
        add(.awaitingApproval, title: "G", at: "2026-11-10T14:50:00+07:00", archived: true)
        let rows = model().unfinished
        #expect(rows.map(\.summary) == ["Tạo lời nhắc: B", "Tạo lời nhắc: C", "Tạo lời nhắc: A"])
        #expect(rows.first?.time == "Hôm nay 14:00")
        #expect(rows.first?.badgeState == .handedOff)
    }

    @Test func emptyUnfinishedAndFirstRunTip() {
        let vm = model()
        #expect(vm.unfinished.isEmpty)
        #expect(vm.showsFirstRunTip)
        add(.succeeded, title: "E", at: "2026-11-10T14:30:00+07:00")
        vm.load()
        #expect(vm.unfinished.isEmpty)
        #expect(!vm.showsFirstRunTip)                                      // P-36: tip only while no drafts
    }

    @Test func sendNeedsNonBlankTextAndSavesDraftFirst() throws {
        let vm = model()
        #expect(!vm.canSend)
        vm.inputText = "  \n "
        #expect(!vm.canSend)
        #expect(vm.send() == nil)
        #expect(repo.saveCount == 0)
        vm.inputText = "  Nhắc tôi 8 giờ sáng mai uống thuốc \n"
        #expect(vm.canSend)
        let id = try #require(vm.send())
        let draft = try #require(repo.draft(id))                           // D-104: saved before S03 opens
        #expect(draft.originalInput == "Nhắc tôi 8 giờ sáng mai uống thuốc")
        #expect(draft.inputMode == .text)
        #expect(draft.steps.isEmpty)
        #expect(vm.inputText.isEmpty && !vm.canSend)
        #expect(!vm.showsFirstRunTip)
    }

    @Test func simpleModeKeepsOnlyCalendarLink() {
        let vm = model()
        #expect(vm.quickLinks == [.calendar, .reminders, .places])
        #expect(vm.quickLinks.map(\.route) == [.calendarToday, .reminders, .places])
        local.settings().simpleMode = true
        #expect(vm.quickLinks == [.calendar])                              // P-40
    }

    @Test func mascotFollowsPetSetting() {
        let vm = model()
        #expect(vm.showsMascot)
        local.settings().petEnabled = false
        #expect(!vm.showsMascot)                                           // D-289
    }

    @Test func quotaLowBannerAtTwoOrLess() {
        let vm = model()
        func ent(_ remaining: Int) -> CachedEntitlement {
            CachedEntitlement(plan: .free, quotaRemaining: remaining, resetsAt: Self.now, fetchedAt: Self.now)
        }
        #expect(vm.quotaLowMessage(nil) == nil)
        #expect(vm.quotaLowMessage(ent(3)) == nil)
        #expect(vm.quotaLowMessage(ent(2))?.text == "Bạn còn 2 lượt AI hôm nay.")
        #expect(vm.quotaLowMessage(ent(0))?.text == "Bạn còn 0 lượt AI hôm nay.")
    }

    @Test func homeKeysExist() {
        let keys = ["home.greeting", "home.mic.caption", "home.input.placeholder", "home.send", "home.camera",
                    "home.link.calendar", "home.link.reminders", "home.link.places", "home.unfinished.title",
                    "home.unfinished.empty", "home.toolbar.history", "home.toolbar.settings", "home.tip.firstRun",
                    "home.mic.a11y", "common.seeAll"]
        for key in keys {
            #expect(String(localized: String.LocalizationValue(key)) != key, "\(key)")
        }
        #expect(UserMessage(key: "home.greeting").text == "Bạn cần mình giúp gì?")
    }
}
