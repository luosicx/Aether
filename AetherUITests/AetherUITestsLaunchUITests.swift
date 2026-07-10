import XCTest

final class AetherUITestsLaunchUITests: XCTestCase {

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
