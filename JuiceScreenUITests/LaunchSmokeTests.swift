import XCTest

/// Verifies the app launches successfully and exits cleanly.
/// More extensive UI tests come in later plans once visible UI exists.
final class LaunchSmokeTests: XCTestCase {

    func test_launchAndQuit() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JUICESCREEN_UI_TEST_MODE"] = "1"
        app.launch()
        // App is LSUIElement — has no main window. Just confirm it didn't crash.
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
    }
}
