import XCTest

final class PluginSettingsUITests: BaseUITestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        navigateBackToRoot(in: Self.app)
        super.tearDown()
    }

    func testNavigateToPluginSettings() {
        let app = Self.app

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()

        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        XCTAssertTrue(pluginLink.waitForExistence(timeout: 5), "应存在插件管理入口")

        pluginLink.tap()
        XCTAssertTrue(app.navigationBars["插件管理"].waitForExistence(timeout: 5),
                      "应进入插件管理页面")
    }

    func testPluginSettingsShowsEmptyState() {
        let app = Self.app

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        pluginLink.tap()

        XCTAssertTrue(app.navigationBars["插件管理"].waitForExistence(timeout: 5))
        let emptyState = app.staticTexts["pluginEmptyState"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5), "应显示空状态提示")
    }

    func testInstallSamplePlugin() {
        let app = Self.app

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        pluginLink.tap()

        let installButton = app.buttons["installSamplePluginButton"]
        if installButton.waitForExistence(timeout: 5) {
            installButton.tap()
            let installedLabel = app.staticTexts["已安装"]
            _ = installedLabel.waitForExistence(timeout: 10)
        }
    }

    func testUninstallPlugin() {
        let app = Self.app

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        pluginLink.tap()

        let uninstallButton = app.buttons["uninstallPluginButton"]
        if uninstallButton.waitForExistence(timeout: 5) {
            uninstallButton.tap()
            _ = app.alerts.firstMatch.waitForExistence(timeout: 3)
        }
    }

    func testViewPluginPermissions() {
        let app = Self.app

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        pluginLink.tap()

        let permissionsButton = app.buttons["viewPluginPermissionsButton"]
        if permissionsButton.waitForExistence(timeout: 5) {
            permissionsButton.tap()
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.waitForExistence(timeout: 3) {
                backButton.tap()
            }
        }
    }
}
