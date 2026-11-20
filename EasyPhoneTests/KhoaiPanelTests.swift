import Foundation
import Testing
@testable import EasyPhoneAI

/// D-325 — "Hỏi Khoai" panel content (the system confirmation shows this before anything is done).
@MainActor
@Suite("Khoai panel (D-325)")
struct KhoaiPanelTests {
    func step(_ kind: String, _ op: String, _ fields: [(String, String)]) throws -> (TaskStep, TaskDraft) {
        let repo = MockTaskRepository()
        let draft = TaskDraft(inputMode: .voice, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh")
        repo.save(draft)
        let engine = TaskEngine(repository: repo)
        #expect(engine.applyParsed(ConversationViewModel.localDraft(kind, op, fields), to: draft))
        return (try #require(draft.steps.first), draft)
    }

    @Test func reminderSummaryShowsTitleAndTime() throws {
        let (s, d) = try step("reminder", "create", [("title", "Uống thuốc"), ("dueDate", "2026-11-20T20:00:00+07:00")])
        let summary = KhoaiSnippet.summary(of: s, timeZoneId: d.timeZoneId)
        #expect(summary.symbol == "bell.fill")
        #expect(summary.lines.first == "Nhắc: Uống thuốc")
        #expect(summary.lines.count == 2 && summary.lines[1].contains("20:00"))
        #expect(summary.spoken.hasPrefix("Nhắc: Uống thuốc, "))
    }

    @Test func callAndDirectionsSummaries() throws {
        let (c, d) = try step("call", "open", [("recipientName", "mẹ"), ("callType", "phone")])
        #expect(KhoaiSnippet.summary(of: c, timeZoneId: d.timeZoneId).lines == ["Gọi cho mẹ"])
        let (p, d2) = try step("place", "open", [("query", "sân bóng học viện kĩ thuật mật mã")])
        #expect(KhoaiSnippet.summary(of: p, timeZoneId: d2.timeZoneId).lines == ["Chỉ đường đến sân bóng học viện kĩ thuật mật mã"])
    }

    @Test func dayIntervalIsTheLocalDay() throws {
        let zone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let range = try #require(KhoaiPanel.interval("2026-11-21", zone))
        #expect(range.start == ISO8601DateFormatter().date(from: "2026-11-21T00:00:00+07:00"))
        #expect(range.duration == 86_400)
        #expect(KhoaiPanel.interval("bad", zone) == nil)
    }

    /// Step 2: what the panel may finish itself; edit / delete / SMS / mail always go to the app (D-108, D-103).
    @Test func whatThePanelMayDo() throws {
        let (r, _) = try step("reminder", "create", [("title", "Uống thuốc"), ("dueDate", "2026-11-20T20:00:00+07:00")])
        #expect(KhoaiPanel.panelKind(r) && !KhoaiPanel.handoffKind(r))
        let (c, _) = try step("call", "open", [("recipientName", "mẹ"), ("callType", "phone")])
        #expect(!KhoaiPanel.panelKind(c) && KhoaiPanel.handoffKind(c))
        let (sms, _) = try step("sms", "open", [("recipientName", "mẹ"), ("body", "Con về muộn"), ("channel", "sms")])
        #expect(!KhoaiPanel.panelKind(sms) && !KhoaiPanel.handoffKind(sms))
        let (del, _) = try step("reminder", "delete", [("title", "Uống thuốc")])
        #expect(!KhoaiPanel.panelKind(del) && !KhoaiPanel.handoffKind(del))
    }

    @Test func quickOpenStrings() {
        for key in ["settings.quickOpen", "settings.quickOpen.intro", "settings.quickOpen.manual", "settings.quickOpen.backTap",
                    "intent.ask.unsupported"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
    }
}
