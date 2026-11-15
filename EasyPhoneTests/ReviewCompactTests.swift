import Foundation
import Testing
@testable import EasyPhoneAI

/// D-292 compact S04: summary card, one-line rows, "Thêm chi tiết", merged calendar time row.
@MainActor
@Suite("S04 compact layout (D-292)")
struct ReviewCompactTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    let repo = MockTaskRepository()

    func open(_ kind: TaskKind, _ op: TaskOperation, _ values: [String: String], targetRef: String? = nil) -> ReviewViewModel {
        let engine = TaskEngine(repository: repo, now: { Self.now })
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: 0.9, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh",
                          steps: [TaskStep(order: 0, kind: kind, operation: op, fields: fields, targetRef: targetRef)])
        repo.save(d)
        engine.revalidate(stepId: d.steps[0].id, in: d)
        return ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: MockPermissionManager())
    }

    @Test func deleteEventShowsSummaryAndHidesEmptyRows() {
        let vm = open(.calendarEvent, .delete, ["title": "Đi đá bóng sân bkc", "startDate": "2026-11-12T09:30:00+07:00",
                                                "endDate": "2026-11-12T10:30:00+07:00", "allDay": "false",
                                                "location": "Sân BKC"], targetRef: "ev")
        #expect(vm.summaryTitle == "Đi đá bóng sân bkc")
        #expect(vm.summaryTime == "Thứ Năm, 12/11 lúc 09:30–10:30")
        #expect(vm.primaryFields.map(\.id) == ["title", "startDate", "location"])    // allDay=false, end folded
        #expect(vm.labelKey(vm.primaryFields[1]) == "review.row.time")
        #expect(Set(vm.detailFields.map(\.id)).isSuperset(of: ["endDate", "allDay", "notes"]))
        #expect(Set(vm.primaryFields.map(\.id) + vm.detailFields.map(\.id)) == Set(vm.visibleFields.map(\.id)))
    }

    @Test func requiredEmptyRowsStayVisible() {
        let vm = open(.reminder, .create, ["title": "Uống thuốc"])                 // dueDate missing
        #expect(vm.primaryFields.map(\.id) == ["title", "dueDate"])
        #expect(vm.detailFields.map(\.id) == ["notes"])
        #expect(vm.summaryTime == nil)
    }

    @Test func callSummaryUsesRecipient() {
        let vm = open(.call, .open, ["recipientName": "mẹ"])
        #expect(vm.summaryTitle == "mẹ")
        #expect(vm.primaryFields.contains { $0.id == "contactId" })                // contact row always shown
    }

    @Test func multiDayAndAllDayTimes() {
        let multi = open(.calendarEvent, .create, ["title": "Đi Đà Lạt", "startDate": "2026-11-12T09:00:00+07:00",
                                                   "endDate": "2026-11-13T18:00:00+07:00"])
        #expect(multi.summaryTime == "Thứ Năm, 12/11 lúc 09:00 – Thứ Sáu, 13/11 lúc 18:00")
        let allDay = open(.calendarEvent, .create, ["title": "Sinh nhật mẹ", "startDate": "2026-11-12T00:00:00+07:00",
                                                    "allDay": "true"])
        #expect(allDay.summaryTime == "Thứ Năm, 12/11 · Cả ngày")
        #expect(allDay.primaryFields.contains { $0.id == "allDay" })                 // true is shown
    }

    @Test func compactStringsExist() {
        for key in ["review.row.time", "review.moreDetails", "review.lessDetails"] {
            #expect(UserMessage(key: key).text != key)
        }
    }
}
