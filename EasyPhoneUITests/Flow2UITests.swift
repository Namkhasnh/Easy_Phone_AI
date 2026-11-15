import XCTest

/// 1C.18b — spec §7 linked flow 2 "Find contact → draft SMS or start call", ARCHITECTURE §13, with
/// `-uiTestScenario uiTest` (mock contact "Nguyễn Văn Minh", mock `/v1/parse`, all permissions granted).
/// The system SMS composer cannot run on the Simulator nor be driven by XCUITest: the SMS path checks the draft and
/// that the app never claims a send it cannot verify (D-102); sending itself is covered by `SMSExecutorTests` and the
/// owner's iPhone check.
@MainActor
final class Flow2UITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest"]
        app.launch()
        XCTAssertTrue(element("screen.S02").waitForExistence(timeout: 10))
    }

    func testSMSFindsContactAndNeverClaimsSent() {
        typeRequest("Nhắn anh Minh là chiều nay em đến muộn")
        XCTAssertTrue(element("screen.S04").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Minh").waitForExistence(timeout: 5))            // contact found on device
        XCTAssertTrue(text(containing: "Chiều nay em đến muộn nhé.").exists)

        tapConfirm()
        XCTAssertTrue(text(containing: "Không thành công").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "chưa gửi được tin nhắn").exists)
    }

    func testCallHandsOffThenAsksOnceOnReturn() {
        typeRequest("Gọi cho anh Minh")
        XCTAssertTrue(element("screen.S04").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Minh").waitForExistence(timeout: 5))

        tapConfirm()
        XCTAssertTrue(text(containing: "Cần hoàn tất").waitForExistence(timeout: 5)) // handedOff, never succeeded

        // Leave and come back, like returning from the Phone app (D-242).
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(element("screen.S08").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Bạn đã gọi xong chưa?").exists)
        app.buttons["Đã xong"].firstMatch.tap()
        XCTAssertTrue(text(containing: "Bạn đã làm xong").waitForExistence(timeout: 5))

        // Asked once only.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(element("screen.S08").waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    private func typeRequest(_ request: String) {
        let field = app.textFields["Hoặc gõ yêu cầu ở đây"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(request)
        app.buttons["Gửi"].firstMatch.tap()
    }

    private func tapConfirm() {
        let confirm = app.buttons["Xác nhận"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
}
