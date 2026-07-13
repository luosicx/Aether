import XCTest

class BaseUITestCase: XCTestCase {
    static var app: XCUIApplication!
    
    override class func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    
    override class func setUpAll() {
        super.setUpAll()
        app = XCUIApplication()
        app.launchArguments += ["UITEST_DISABLE_NETWORK", "UITEST_RESET_DATA", "UITEST_DISABLE_SPLASH"]
        app.launch()
    }
    
    override class func tearDownAll() {
        if app != nil && app.state == .runningForeground {
            app.terminate()
        }
        super.tearDownAll()
    }
    
    func inputField(in app: XCUIApplication) -> XCUIElement {
        let tv = app.textViews.matching(identifier: "messageInputField").firstMatch
        if tv.waitForExistence(timeout: 3) { return tv }
        return app.textFields.matching(identifier: "messageInputField").firstMatch
    }
    
    func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let window = app.windows.firstMatch
        let topPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05))
        topPoint.tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }
    
    func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 8) {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxAttempts {
            let scroller = app.tables.firstMatch.exists
                ? app.tables.firstMatch
                : (app.collectionViews.firstMatch.exists
                    ? app.collectionViews.firstMatch
                    : app.scrollViews.firstMatch)
            scroller.swipeUp()
            attempts += 1
            _ = element.waitForExistence(timeout: 1)
        }
    }
    
    func waitForToggleValue(_ toggle: XCUIElement, equals expected: String, timeout: TimeInterval = 0.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (toggle.value as? String) == expected { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return (toggle.value as? String) == expected
    }
    
    func waitForToggleChange(_ toggle: XCUIElement, from oldValue: String?, timeout: TimeInterval = 0.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (toggle.value as? String) != oldValue { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return (toggle.value as? String) != oldValue
    }
    
    func waitForInputContains(_ field: XCUIElement, substring: String, timeout: TimeInterval = 0.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let v = field.value as? String, v.contains(substring) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return (field.value as? String)?.contains(substring) ?? false
    }
    
    func navigateBackToRoot(in app: XCUIApplication) {
        while app.navigationBars.count > 0 {
            let backButton = app.navigationBars.firstMatch.buttons["Back"]
                .firstMatch.exists ? app.navigationBars.firstMatch.buttons["Back"].firstMatch
                : app.navigationBars.firstMatch.buttons.firstMatch
            if backButton.waitForExistence(timeout: 2) {
                backButton.tap()
            } else {
                break
            }
        }
        _ = app.staticTexts["以太"].waitForExistence(timeout: 5)
    }
}
