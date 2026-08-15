import XCTest

final class CentralWorkoutFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["APE_X_UI_TESTING"] = "1"
        app.launch()
    }

    func testCentralWorkoutFlowStartsCompletesAndSavesSession() {
        let workout = app.descendants(matching: .any)["workout-card-UI Test Workout"]
        XCTAssertTrue(workout.waitForExistence(timeout: 5))
        workout.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.15)).tap()

        let start = app.buttons["Start session"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        let reps = app.textFields["Reps for set 1"]
        XCTAssertTrue(reps.exists)
        reps.tap()
        reps.typeText("10")
        app.buttons["Mark set complete"].tap()

        // Dismissing the one-second rest sheet exercises the timer path without
        // making the test depend on notification authorization.
        if app.buttons["Skip"].waitForExistence(timeout: 2) {
            app.buttons["Skip"].tap()
        }
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.staticTexts["How was your workout?"].waitForExistence(timeout: 3))
        app.buttons["Rating 5 of 5"].tap()
        app.buttons["End workout"].tap()
        app.buttons["Save Session"].tap()
        XCTAssertTrue(app.staticTexts["UI Test Workout"].waitForExistence(timeout: 5))
    }

    func testBackgroundingAndInterruptionRelaunchesCleanly() {
        openWorkout()
        app.buttons["Start session"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))

        XCUIDevice.shared.press(.home)
        app.launch()

        XCTAssertTrue(workoutCard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Workouts"].isSelected)
    }

    func testCentralFlowHasAccessibleNamesAndActions() {
        XCTAssertTrue(app.buttons["Create workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Session history"].exists)
        XCTAssertTrue(app.tabBars.buttons["Workouts"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Exercises"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isHittable)

        openWorkout()
        XCTAssertTrue(app.buttons["Edit workout"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Workout options"].exists)
        XCTAssertTrue(app.buttons["Start session"].isHittable)
    }

    func testAccessibilityDynamicTypeKeepsCentralActionsReachable() {
        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["UI Test Workout"].waitForExistence(timeout: 5))
        openWorkout()
        let start = app.buttons["Start session"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertTrue(start.isHittable, "The primary workout action must remain reachable at AX XXXL")
        XCTAssertTrue(app.buttons["Edit workout"].exists)
    }

    private var workoutCard: XCUIElement {
        app.descendants(matching: .any)["workout-card-UI Test Workout"]
    }

    private func openWorkout() {
        XCTAssertTrue(workoutCard.waitForExistence(timeout: 5))
        workoutCard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.15)).tap()
    }
}
