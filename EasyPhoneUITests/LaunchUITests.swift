import XCTest

/// 1C.18a — ARCHITECTURE §13: the app starts with `-uiTestScenario uiTest` (mocks, signed in, in-memory store).
final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testUITestScenarioOpensHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.S02"].waitForExistence(timeout: 10))
    }
}
