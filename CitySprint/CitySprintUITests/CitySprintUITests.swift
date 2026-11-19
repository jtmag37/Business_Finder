import XCTest

/// UI tests run with `-uiTesting`: in-memory progress, Apple services off and
/// a short, obstacle-free test course so the results flow is deterministic.
final class CitySprintUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
    }

    private func launch(extra: [String] = []) {
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 10))
    }

    private func startFirstLevel() {
        app.buttons["playButton"].tap()
        let nyc = app.buttons["city_newYork"]
        XCTAssertTrue(nyc.waitForExistence(timeout: 5))
        nyc.tap()
        let level = app.buttons["level_nyc_1"]
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        level.tap()
        let tutorial = app.buttons["tutorialDismiss"]
        if tutorial.waitForExistence(timeout: 5) { tutorial.tap() }
    }

    func testRideFirstLevelToResults() {
        launch()
        startFirstLevel()
        let title = app.staticTexts["resultsTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "results should appear after the test course")
        XCTAssertTrue(app.staticTexts["resultScore"].exists)
        app.buttons["exitButton"].tap()
        XCTAssertTrue(app.buttons["level_nyc_2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["level_nyc_2"].isEnabled, "finishing level 1 unlocks level 2")
    }

    func testRetryFromResults() {
        launch()
        startFirstLevel()
        XCTAssertTrue(app.staticTexts["resultsTitle"].waitForExistence(timeout: 30))
        app.buttons["retryButton"].tap()
        XCTAssertTrue(app.buttons["pauseButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["resultsTitle"].waitForExistence(timeout: 30))
    }

    func testPauseResumeAndQuit() {
        launch()
        startFirstLevel()
        let pause = app.buttons["pauseButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertTrue(app.buttons["resumeButton"].waitForExistence(timeout: 5))
        app.buttons["resumeButton"].tap()
        pause.tap()
        app.buttons["quitButton"].tap()
        XCTAssertTrue(app.buttons["level_nyc_1"].waitForExistence(timeout: 5))
    }

    func testLockedCityIsDisabledUntilStarsEarned() {
        launch()
        app.buttons["playButton"].tap()
        let paris = app.buttons["city_paris"]
        XCTAssertTrue(paris.waitForExistence(timeout: 5))
        XCTAssertFalse(paris.isEnabled)
        XCTAssertTrue(app.staticTexts["nextUnlockHint"].exists || app.otherElements["nextUnlockHint"].exists)
    }

    func testSeededStarsUnlockNextCity() {
        launch(extra: ["-seedStars", "9"])
        app.buttons["playButton"].tap()
        let paris = app.buttons["city_paris"]
        XCTAssertTrue(paris.waitForExistence(timeout: 5))
        XCTAssertTrue(paris.isEnabled)
    }

    func testDailyChallengeFlow() {
        launch()
        app.buttons["dailyButton"].tap()
        let play = app.buttons["playDailyButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.staticTexts["resultsTitle"].waitForExistence(timeout: 30))
        app.buttons["exitButton"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
    }

    func testSettingsToggles() {
        launch()
        app.buttons["settingsButton"].tap()
        let assist = app.switches["assistToggle"]
        XCTAssertTrue(assist.waitForExistence(timeout: 5))
        let before = assist.value as? String
        // Tap the switch itself (right edge of the row), not the label.
        assist.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertNotEqual(assist.value as? String, before)
        XCTAssertTrue(app.switches["colorblindToggle"].exists)
        XCTAssertTrue(app.switches["reduceMotionToggle"].exists)
    }

    func testGarageShowsCosmetics() {
        launch()
        app.buttons["garageButton"].tap()
        XCTAssertTrue(app.segmentedControls["garageSlotPicker"].waitForExistence(timeout: 5)
                      || app.otherElements["garageSlotPicker"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["Classic Red"].exists)
    }

    /// Captures store-style screenshots of real levels (kept as attachments;
    /// CI exports them as an artifact).
    func testCaptureScreenshots() {
        launch(extra: ["-seedStars", "240", "-uiTestRealLevels"])
        snapshot("01-home")
        app.buttons["playButton"].tap()
        XCTAssertTrue(app.buttons["city_london"].waitForExistence(timeout: 5))
        snapshot("02-world-map")
        for (city, code) in [("london", "lon"), ("tokyo", "tyo"), ("amsterdam", "ams"), ("paris", "par")] {
            let card = app.buttons["city_\(city)"]
            if !card.isHittable { app.swipeUp() }
            card.tap()
            let level = app.buttons["level_\(code)_4"]
            XCTAssertTrue(level.waitForExistence(timeout: 5))
            if city == "london" { snapshot("03-city") }
            level.tap()
            XCTAssertTrue(app.buttons["pauseButton"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 4)
            snapshot("04-ride-\(city)")
            app.buttons["pauseButton"].tap()
            app.buttons["quitButton"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["garageButton"].tap()
        XCTAssertTrue(app.buttons["Classic Red"].waitForExistence(timeout: 5))
        snapshot("05-garage")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
