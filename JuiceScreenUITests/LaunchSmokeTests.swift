import XCTest

/// Verifies the app launches successfully and exits cleanly.
/// More extensive UI tests come in later plans once visible UI exists.
final class LaunchSmokeTests: XCTestCase {

    func test_launchAndQuit() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JUICESCREEN_UI_TEST_MODE"] = "1"
        app.launch()
        // LSUIElement = true means the process runs as a menu-bar agent and never
        // takes foreground focus. .runningForeground would only happen if the app
        // grabbed key focus, which it deliberately doesn't. Pass on any "running"
        // state; fail only if the process didn't start.
        XCTAssertNotEqual(app.state, .notRunning, "App failed to launch")
        XCTAssertNotEqual(app.state, .unknown, "App in unknown state after launch")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
    }
}
