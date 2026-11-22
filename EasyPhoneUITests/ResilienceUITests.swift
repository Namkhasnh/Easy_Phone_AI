import XCTest

/// 1G.10 — resilience (spec §5.5, §12 "network loss, denied permission, app kill and return-from-other-app never lose
/// progress", ARCHITECTURE §11, D-104) on the Simulator with `-uiTestScenario uiTest` plus the test-only options
/// `-uiTestDisk` (drafts in an on-disk test store, so a killed app finds them again), `-uiTestOffline`,
/// `-uiTestDenied`. Return from another app is `Flow2UITests.testCallHandsOffThenAsksOnceOnReturn`.
@MainActor
final class ResilienceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Kill the app on Review, open it again: the draft is in "Việc chưa xong" and reopens with the same content.
    func testKilledAppKeepsTheDraft() {
        launch(reset: true)
        typeRequest("Nhắn anh Minh là chiều nay em đến muộn")
        XCTAssertTrue(element("screen.S04").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Chiều nay em đến muộn nhé.").waitForExistence(timeout: 5))

        app.terminate()
        launch(reset: false)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Soạn tin nhắn: anh Minh")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the draft is not in Việc chưa xong after a relaunch")
        tapScrolling(row)
        XCTAssertTrue(element("screen.S04").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Chiều nay em đến muộn nhé.").waitForExistence(timeout: 5))
    }

    /// No network: the request text stays, the offline message says the draft is saved; after a relaunch with the
    /// network back the same request is still there and goes through.
    func testOfflineKeepsTheRequest() {
        launch(reset: true, extra: ["-uiTestOffline", "YES"])
        typeRequest("Nhắn anh Minh là chiều nay em đến muộn")
        XCTAssertTrue(text(containing: "Không có mạng").waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@",
                                  "chiều nay em đến muộn", "chiều nay em đến muộn")).firstMatch.exists,
                      "the typed request was lost")
        snapshot("offline")

        app.terminate()
        launch(reset: false)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chưa gửi được")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the offline request is not in Việc chưa xong")
        snapshot("offline_relaunch")
        tapScrolling(row)                                  // network back: S03 sends the same words, then S04
        XCTAssertTrue(element("screen.S04").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Chiều nay em đến muộn nhé.").waitForExistence(timeout: 5))
    }

    /// Contacts denied: nothing is sent; S04 keeps the draft, the contact row is "Chưa có", "Xác nhận" stays off with the
    /// reason under it (the row opens the system contact picker, which needs no permission). The draft survives a kill.
    func testDeniedPermissionKeepsTheDraftAndNeverSends() {
        launch(reset: true, extra: ["-uiTestDenied", "YES"])
        typeRequest("Nhắn anh Minh là chiều nay em đến muộn")
        XCTAssertTrue(element("screen.S04").waitForExistence(timeout: 10))
        snapshot("denied")
        XCTAssertTrue(text(containing: "Chiều nay em đến muộn nhé.").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Xác nhận"].firstMatch.isEnabled)
        XCTAssertTrue(text(containing: "trước khi xác nhận").exists)

        app.terminate()
        launch(reset: false)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Soạn tin nhắn: anh Minh")).firstMatch
            .waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    private func launch(reset: Bool, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest", "-uiTestDisk", "YES",
                               "-uiTestResetStore", reset ? "YES" : "NO"] + extra
        app.launch()
        XCTAssertTrue(element("screen.S02").waitForExistence(timeout: 10))
    }

    private func typeRequest(_ request: String) {
        let field = app.textFields["Hoặc gõ yêu cầu ở đây"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(request)
        app.buttons["Gửi"].firstMatch.tap()
    }

    /// Opens the row from S14 "Lịch sử" (same rows as S02 "Việc chưa xong", near the top of the screen there).
    private func tapScrolling(_ element: XCUIElement) {
        let label = element.label
        app.buttons["Lịch sử"].firstMatch.tap()
        let row = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row missing in Lịch sử")
        row.tap()
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
}
