import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.13 — UI_SCREENS S14, spec §6.10 AC1–AC2, DATA_MODEL §8, D-244.
@MainActor
@Suite("History (UI_SCREENS S14)")
struct HistoryTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = Validator.parseDateTime("2026-11-10T15:00:00+07:00")!

    let repo = MockTaskRepository()

    func add(_ kind: TaskKind, _ states: [TaskState], _ values: [String: String] = [:], at: String) -> TaskDraft {
        let steps = states.enumerated().map { i, s in
            TaskStep(order: i, kind: i == 0 ? kind : .reminder, operation: i == 0 && (kind == .call || kind == .sms) ? .open : .create,
                     state: s, fields: values.map { Field(id: $0.key, type: .text, value: $0.value) })
        }
        let d = TaskDraft(inputMode: .text, originalInput: "x", steps: steps)
        repo.save(d)
        d.updatedAt = Validator.parseDateTime(at)!
        return d
    }

    func model() -> HistoryViewModel {
        let vm = HistoryViewModel(repository: repo, now: { Self.now }, timeZone: Self.tz)
        vm.load()
        return vm
    }

    @Test func groupsInFixedOrderWithoutEmptyOnes() {
        add(.reminder, [.cancelled], at: "2026-11-10T09:00:00+07:00")
        add(.sms, [.awaitingApproval], ["recipientName": "anh Minh"], at: "2026-11-10T14:05:00+07:00")
        add(.call, [.handedOff], at: "2026-11-09T20:30:00+07:00")
        let vm = model()
        #expect(vm.sections.map(\.group) == [.needsYou, .waiting, .cancelled])   // no "done" section
    }

    @Test func rowTextsPerS14() {
        let sms = add(.sms, [.awaitingApproval], ["recipientName": "anh Minh"], at: "2026-11-10T14:05:00+07:00")
        add(.call, [.handedOff], ["recipientName": "mẹ"], at: "2026-11-09T20:30:00+07:00")
        add(.reminder, [.succeeded], ["title": "Uống thuốc"], at: "2026-11-02T08:00:00+07:00")
        let vm = model()
        let first = vm.sections[0].rows[0]
        #expect(first.id == sms.id)
        #expect(first.summary == "Soạn tin nhắn: anh Minh")
        #expect(first.time == "Hôm nay 14:05")
        #expect(first.symbol == "message" && first.badgeState == .awaitingApproval && first.stepsText == nil)
        #expect(vm.sections[1].rows[0].time == "Hôm qua 20:30")
        let call = vm.sections[1].rows[0]
        #expect(UserMessage(key: call.badgeState.labelKey, args: call.badgeArgs).text == "Cần hoàn tất trong Điện thoại")
        #expect(vm.sections[2].rows[0].time == "Thứ Hai, 02/11 lúc 08:00")
    }

    @Test func multiStepRowShowsProgressAndGroupStep() {
        add(.calendarEvent, [.succeeded, .awaitingApproval], ["title": "Khám răng"], at: "2026-11-10T10:00:00+07:00")
        let row = model().sections[0].rows[0]
        #expect(row.stepsText == "1/2 bước")
        #expect(row.badgeState == .awaitingApproval)          // the step that puts the draft in "Cần bạn làm tiếp"
        #expect(row.summary == "Tạo lời nhắc: Khám răng")      // current step = first not closed (D-244)
    }

    @Test func newestFirstAndHideRemovesRow() {
        let old = add(.reminder, [.failed], ["title": "A"], at: "2026-11-08T10:00:00+07:00")
        let new = add(.reminder, [.needsInfo], ["title": "B"], at: "2026-11-10T10:00:00+07:00")
        let vm = model()
        #expect(vm.sections[0].rows.map(\.id) == [new.id, old.id])
        vm.hide(new.id)
        #expect(vm.sections[0].rows.map(\.id) == [old.id])
        #expect(repo.draft(new.id)?.isArchived == true)       // hidden, not deleted
    }

    @Test func emptyHistory() {
        #expect(model().isEmpty)
    }

    /// 1G.10 (D-104): a request that never got an answer (offline, killed while sending) is listed and reopens S03;
    /// an answered one without steps ("Chưa hỗ trợ", a screen opened) and an empty one are not.
    @Test func unansweredRequestIsListedAndOpensConversation() throws {
        let unsent = TaskDraft(inputMode: .text, originalInput: "Nhắn anh Minh là chiều nay em đến muộn")
        let answered = TaskDraft(inputMode: .text, originalInput: "Đặt xe đi sân bay")
        answered.markAnswered("req_1")
        let empty = TaskDraft(inputMode: .voice, originalInput: "  ")
        for d in [unsent, answered, empty] { repo.save(d) }
        let rows = DraftRowBuilder(now: { Self.now }, timeZone: Self.tz)
        let row = try #require(rows.row(unsent))
        #expect(row.opensConversation && row.route == .conversation(unsent.id))
        #expect(row.summary.contains("Nhắn anh Minh") && row.stepsText == "Chưa gửi được. Bấm để gửi lại.")
        #expect(rows.row(answered) == nil && rows.row(empty) == nil)
        #expect(model().sections.flatMap(\.rows).map(\.id) == [unsent.id])
    }

    /// Requests saved before this change were never marked; the launch marks them once so they do not show up.
    @Test func legacyRequestsAreMarkedOnce() async throws {
        let old = TaskDraft(inputMode: .text, originalInput: "Đặt đồ ăn")
        repo.save(old)
        let defaults = try #require(UserDefaults(suiteName: "legacy-\(UUID())"))
        let verifier = LaunchVerifier(repository: repo, engine: TaskEngine(repository: repo, executors: [:]),
                                      defaults: defaults)
        verifier.markLegacyRequestsOnce()
        #expect(!old.isUnanswered)
        let later = TaskDraft(inputMode: .text, originalInput: "Nhắn mẹ")
        repo.save(later)
        verifier.markLegacyRequestsOnce()
        #expect(later.isUnanswered)                                   // only once
    }
}
