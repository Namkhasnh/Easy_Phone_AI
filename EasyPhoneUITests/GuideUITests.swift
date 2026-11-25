import XCTest

/// 4H.3 / 4H.5: "làm sao kết nối wifi" typed in S02 → S23 (curated, no unit) → "Bước tiếp" → the Live Activity
/// "Bước 2/4" on the Lock Screen while the app is in the background → back in the app, the same step.
/// The Hỏi Khoai panel itself (an App Intent) cannot be driven by XCUITest: checked on the iPhone.
@MainActor
final class GuideUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.S02"].waitForExistence(timeout: 10))
    }

    func testGuideStepsAndLiveActivity() throws {
        let field = app.textFields["Hoặc gõ yêu cầu ở đây"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Làm sao kết nối wifi")
        app.buttons["Gửi"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.S23"].waitForExistence(timeout: 10))
        XCTAssertTrue(label("Bước 1/4").waitForExistence(timeout: 5))
        attach("S23 bước 1")
        app.buttons["Bước tiếp"].firstMatch.tap()
        XCTAssertTrue(label("Bước 2/4").waitForExistence(timeout: 5))
        attach("S23 bước 2")

        // Background → the Live Activity on the Home Screen / Dynamic Island and the Lock Screen.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        sleep(2)
        attach("Màn hình chính (Dynamic Island)", springboard.screenshot())
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(2)
        XCUIDevice.shared.press(.home)                                       // wake the Lock Screen
        sleep(2)
        attach("Màn hình khoá", springboard.screenshot())
        let activity = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Bước 2/4")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 5), "no Live Activity on the Lock Screen")
    }

    private func label(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func attach(_ name: String, _ shot: XCUIScreenshot? = nil) {
        let a = XCTAttachment(screenshot: shot ?? app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
