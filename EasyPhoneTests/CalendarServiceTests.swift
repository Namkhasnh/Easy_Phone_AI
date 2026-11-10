import EventKit
import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.2 — ARCHITECTURE §4.2, spec §6.4 AC2, D-225 (`easyphone:<stepId>`), DATA_MODEL §3.5.
@Suite("CalendarService (EventKit)")
struct CalendarServiceTests {
    static let t0 = Validator.parseDateTime("2026-11-13T14:00:00+07:00")!
    static func at(_ hours: Double) -> Date { t0 + hours * 3600 }

    static func event(_ id: String, _ title: String, _ start: Double, _ end: Double, allDay: Bool = false,
                      recurring: Bool = false) -> EventSummary {
        EventSummary(id: id, title: title, start: at(start), end: at(end), isAllDay: allDay, calendarName: "Lịch",
                     isRecurring: recurring)
    }

    // MARK: - Pure rules

    @Test func stepTagRoundTrip() {
        let id = UUID()
        let tag = StepTag.make(id)
        #expect(tag == "easyphone:\(id.uuidString)")
        #expect(StepTag.read(URL(string: tag)) == tag)
        #expect(StepTag.read(URL(string: "https://example.com")) == nil)
        #expect(StepTag.read(nil) == nil)
    }

    @Test func overlapIsHalfOpenAndSkipsAllDay() {
        let e = Self.event("a", "Khám răng", 0, 1)
        #expect(e.overlaps(start: Self.at(0.5), end: Self.at(2)))
        #expect(!e.overlaps(start: Self.at(1), end: Self.at(2)))          // touching ends do not conflict
        #expect(!e.overlaps(start: Self.at(-1), end: Self.at(0)))
        #expect(!Self.event("b", "Sinh nhật", -14, 10, allDay: true).overlaps(start: Self.at(0), end: Self.at(1)))
    }

    @Test func titleMatchIgnoresDiacriticsAndCase() {
        let e = Self.event("a", "Khám răng bác sĩ Hùng", 0, 1)
        #expect(e.matches(title: "kham rang"))
        #expect(e.matches(title: "KHÁM RĂNG"))
        #expect(e.matches(title: nil))
        #expect(!e.matches(title: "họp lớp"))
    }

    @Test func searchSortsByDistanceToDate() {
        let sorted = CalendarSearch.sort([Self.event("far", "x", 48, 49), Self.event("near", "x", 2, 3),
                                          Self.event("before", "x", -5, -4)], near: Self.at(0))
        #expect(sorted.map(\.id) == ["near", "before", "far"])
    }

    // MARK: - EventKit mapping (no access needed to build EKEvent objects)

    @Test func applyAndSummaryRoundTrip() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let input = EventInput(title: "Khám răng", start: Self.at(0), end: Self.at(1), location: "Nha khoa Hoa Sen",
                               notes: "Mang sổ khám", alertMinutesBefore: 60)
        let tag = StepTag.make(UUID())
        LiveCalendarService.apply(input, stepTag: tag, to: event)
        let s = LiveCalendarService.summary(event)
        #expect(s.title == "Khám răng" && s.start == Self.at(0) && s.end == Self.at(1) && !s.isAllDay)
        #expect(s.location == "Nha khoa Hoa Sen" && s.notes == "Mang sổ khám")
        #expect(s.alertMinutesBefore == 60)
        #expect(s.stepTag == tag)                                          // D-225
        #expect(!s.isRecurring)

        LiveCalendarService.apply(EventInput(title: "Khám răng", start: Self.at(0), end: Self.at(1)),
                                  stepTag: tag, to: event)
        let cleared = LiveCalendarService.summary(event)
        #expect(cleared.alertMinutesBefore == nil && cleared.location == nil && cleared.notes == nil)
    }

    // MARK: - Mock (same contract the executors rely on, 1C.3)

    @Test func mockSaveFindByTagUpdateDelete() async throws {
        let cal = MockCalendarService()
        let tag = StepTag.make(UUID())
        let input = EventInput(title: "Khám răng", start: .now + 3600, end: .now + 7200)
        let id = try await cal.save(input, stepTag: tag, existing: nil)
        #expect(try await cal.find(identifier: id)?.title == "Khám răng")
        #expect(try await cal.find(stepTag: tag)?.id == id)                 // lost identifier → found by tag (D-105)
        var changed = input
        changed.title = "Khám răng (đổi giờ)"
        #expect(try await cal.save(changed, stepTag: tag, existing: id) == id)
        #expect(cal.all.count == 1 && cal.saveCount == 2)
        try await cal.delete(identifier: id)
        #expect(try await cal.find(identifier: id) == nil)
        await #expect(throws: ServiceError.notFound) { try await cal.delete(identifier: id) }
        await #expect(throws: ServiceError.notFound) { _ = try await cal.save(input, stepTag: tag, existing: "nope") }
    }

    @Test func mockConflictsAndSearch() async throws {
        let cal = MockCalendarService([Self.event("a", "Khám răng", 0, 1), Self.event("b", "Họp lớp", 3, 4),
                                       Self.event("c", "Sinh nhật mẹ", -14, 10, allDay: true),
                                       Self.event("d", "Khám răng định kỳ", 24, 25, recurring: true)])
        #expect(try await cal.conflicts(start: Self.at(0.5), end: Self.at(3.5)).map(\.id) == ["a", "b"])
        #expect(try await cal.search(title: "kham rang", near: Self.at(0)).map(\.id) == ["a"])   // recurring skipped
    }

    @Test func mockWriteOnlyCannotReadButCanSave() async throws {
        let cal = MockCalendarService(access: .writeOnly)
        await #expect(throws: ServiceError.permissionDenied(.calendar)) {
            _ = try await cal.conflicts(start: Self.at(0), end: Self.at(1))
        }
        _ = try await cal.save(EventInput(title: "x", start: Self.at(0), end: Self.at(1)), stepTag: "easyphone:x",
                               existing: nil)
        cal.setAccess(.denied)
        await #expect(throws: ServiceError.permissionDenied(.calendar)) {
            _ = try await cal.save(EventInput(title: "x", start: Self.at(0), end: Self.at(1)), stepTag: "easyphone:y",
                                   existing: nil)
        }
    }

    @Test func liveWithoutAccessThrowsPermissionDenied() async {
        // Simulator test host never granted calendar access → reads must refuse instead of returning nothing.
        guard EKEventStore.authorizationStatus(for: .event) != .fullAccess else { return }
        let cal = LiveCalendarService()
        await #expect(throws: ServiceError.permissionDenied(.calendar)) {
            _ = try await cal.events(in: DateInterval(start: Self.at(0), end: Self.at(1)))
        }
    }
}
