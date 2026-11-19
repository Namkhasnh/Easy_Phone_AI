import XCTest

/// D-317: S15 first screen = groups only; each group opens its own page.
@MainActor
final class SettingsUITests: XCTestCase {
    func testGroupsOpenTheirOwnPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.S02"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Cài đặt"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.S15"].firstMatch.waitForExistence(timeout: 5))
        for row in ["account", "voice", "display", "memory", "connections"] {
            XCTAssertTrue(app.descendants(matching: .any)["settings.row.\(row)"].firstMatch.exists, row)
        }
        XCTAssertFalse(app.switches.firstMatch.exists)                         // no toggles on the first screen

        app.descendants(matching: .any)["settings.row.voice"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.S15.voice"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()                           // back

        app.swipeUp()                                                          // the last group may be below the fold
        XCTAssertTrue(app.descendants(matching: .any)["settings.row.data"].firstMatch.exists)
        app.descendants(matching: .any)["settings.row.about"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Chính sách quyền riêng tư"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Chính sách quyền riêng tư"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.legal.privacy"].firstMatch.waitForExistence(timeout: 5))
    }
}
