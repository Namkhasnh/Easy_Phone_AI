import XCTest

/// 1D.11 — spec §7 linked flow 1 "Appointment photo → edit fields → create event + reminder" (ARCHITECTURE §6.4,
/// §13) with `-uiTestScenario uiTest`: mock OCR (`OCRResult.sample`), mock `/v1/extract` (`ExtractResponse.mock`,
/// date moved to tomorrow 09:30), every permission granted, in-memory mock calendar / reminders. Any library photo
/// works because OCR is mocked; the Simulator library always has its sample photos.
@MainActor
final class Flow1UITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        throw XCTSkip("D-302: photo / OCR paused, the S02 entry is hidden")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest"]
        app.launch()
        XCTAssertTrue(element("screen.S02").waitForExistence(timeout: 10))
    }

    func testPhotoToCalendarEvent() {
        openOCRStep()
        XCTAssertTrue(text(containing: "Phòng khám Nha khoa An Bình").exists)
        XCTAssertTrue(app.buttons["Xem ảnh gốc"].firstMatch.exists)                    // fields link to the photo

        // Edit a field (spec §6.3 AC4): S05 for "Tên lịch hẹn".
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tên lịch hẹn")).firstMatch.tap()
        let editor = app.textFields.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.clearAndType("Khám răng")
        app.buttons["Lưu"].firstMatch.tap()
        XCTAssertTrue(text(containing: "Khám răng").waitForExistence(timeout: 5))

        app.buttons["ocr.nextAction.calendarEvent"].tap()
        tap("Tiếp tục")

        // The linked calendar step (Bước 2/2) carries the edited title; nothing is created before "Xác nhận" (D-100).
        XCTAssertTrue(text(containing: "Khám răng").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "215 Hồng Bàng").exists)
        tap("Xác nhận")
        expectAllDone()
    }

    func testPhotoToReminder() {
        openOCRStep()
        app.buttons["ocr.nextAction.reminder"].tap()
        tap("Tiếp tục")
        XCTAssertTrue(text(containing: "Phòng khám Nha khoa An Bình").waitForExistence(timeout: 5))
        tap("Xác nhận")
        expectAllDone()
    }

    // MARK: - Helpers

    /// S02 → S09 → library photo → mock OCR + extract → S04 with the `ocr` step.
    private func openOCRStep() {
        app.buttons["Chụp ảnh giấy tờ"].firstMatch.tap()
        XCTAssertTrue(element("screen.S09").waitForExistence(timeout: 5))
        app.buttons["Chọn ảnh có sẵn"].firstMatch.tap()
        pickFirstLibraryPhoto()
        XCTAssertTrue(element("screen.S04").waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Tiếp tục"].firstMatch.waitForExistence(timeout: 5))
    }

    /// The system photo picker runs out of process but its cells are reachable from the app's tree.
    private func pickFirstLibraryPhoto() {
        let photo = app.images.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR label CONTAINS %@",
                                                    "PXGGridLayout", "Photo")).firstMatch
        if photo.waitForExistence(timeout: 10) {
            photo.tap()
        } else {
            let cell = app.scrollViews.images.firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "no photo in the picker")
            cell.tap()
        }
    }

    /// Both steps closed: the last step's card says `result.allDone` and its badge `state.succeeded` (D-124: the
    /// mock calendar / reminders store returned an identifier = evidence).
    private func expectAllDone() {
        XCTAssertTrue(text(containing: "Xong rồi!").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Trạng thái: Đã xong").exists)
        XCTAssertTrue(text(containing: "Bước 2/2").exists)
        XCTAssertTrue(app.buttons["Xong"].firstMatch.exists)
    }

    private func tap(_ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), label)
        XCTAssertTrue(button.isEnabled, label)
        button.tap()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func text(containing value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        if let value = value as? String, !value.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        typeText(text)
    }
}
