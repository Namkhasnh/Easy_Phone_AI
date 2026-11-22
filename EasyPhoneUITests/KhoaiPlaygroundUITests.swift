import XCTest

/// D-327 / 1G.K2: the Debug-only "Xem thử Khoai" screen opens from S15 › Nâng cao; tap shows a tip, pet the reply.
@MainActor
final class KhoaiPlaygroundUITests: XCTestCase {
    func testPlaygroundReactsToTapAndPet() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.S02"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Cài đặt"].firstMatch.tap()
        let advanced = app.descendants(matching: .any)["settings.row.advanced"].firstMatch
        for _ in 0..<3 where !advanced.isHittable { app.swipeUp() }
        advanced.tap()
        let row = app.buttons["Xem thử Khoai"].firstMatch
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.khoaiPlayground"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "1 hint")
        for i in 1...3 {                                    // video style, "Hỏi thêm" clip: frames change over time
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, "1 video \(i)")
        }

        app.buttons["Chạm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bạn thử nói: “Nhắc tôi 8 giờ sáng uống thuốc”"].waitForExistence(timeout: 3))
        attach(app, "2 tap tip")

        app.buttons["Xoa đầu"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hihi, nhột quá!"].waitForExistence(timeout: 3))
        attach(app, "3 pet")

        app.buttons["Hỏi thêm"].firstMatch.tap()
        attach(app, "4 asking")
    }

    /// D-327 S02 v2: Khoai's bubble greets, a tap shows a tip with "Đọc to" / "Gợi ý khác"; the mic still opens S03.
    func testHomeAndListeningKhoai() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", "uiTest"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.S02"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bạn cần mình giúp gì?"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, "S02 greeting")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33)).tap()   // on Khoai
        XCTAssertTrue(app.buttons["Gợi ý khác"].waitForExistence(timeout: 3))
        attach(app, "S02 tip")
        app.buttons["Gợi ý khác"].tap()
        XCTAssertTrue(app.staticTexts["Bạn thử nói: “Gọi cho mẹ”"].waitForExistence(timeout: 3))
        app.buttons["Nói yêu cầu"].firstMatch.tap()
        _ = app.descendants(matching: .any)["screen.S03"].firstMatch.waitForExistence(timeout: 5)
        // The mock transcript ends listening at once (→ S04), so S03's listening Khoai is checked on the iPhone.
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
