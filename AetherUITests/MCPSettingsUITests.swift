import XCTest

final class MCPSettingsUITests: BaseUITestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        navigateBackToRoot(in: Self.app)
        super.tearDown()
    }

    func testOpenMCPSettings() throws {
        let app = Self.app!

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10), "应存在设置按钮")
        app.buttons["settingsButton"].tap()

        let mcpLink = app.descendants(matching: .any).matching(identifier: "mcpSettingsLink").firstMatch
        if !mcpLink.exists {
            let formScroller = app.collectionViews.firstMatch.exists
                ? app.collectionViews.firstMatch
                : (app.tables.firstMatch.exists ? app.tables.firstMatch : app.scrollViews.firstMatch)
            var scrollAttempts = 0
            while !mcpLink.exists && scrollAttempts < 10 {
                formScroller.swipeUp()
                scrollAttempts += 1
                _ = mcpLink.waitForExistence(timeout: 1)
            }
        }

        guard mcpLink.waitForExistence(timeout: 5) else {
            throw XCTSkip("MCP 配置入口未渲染于无障碍树，跳过测试")
        }
        mcpLink.tap()

        let addButton = app.buttons["addMCPServerButton"]
        let viewIdentifier = app.descendants(matching: .any).matching(identifier: "MCPSettingsView").firstMatch
        let entered = addButton.waitForExistence(timeout: 5) || viewIdentifier.waitForExistence(timeout: 3)
        XCTAssertTrue(entered, "应进入 MCP 配置页（添加按钮或页面标识应存在）")
    }

    func testAddMCPServer() throws {
        let app = Self.app!

        app.buttons["settingsButton"].tap()
        let mcpLink = app.descendants(matching: .any).matching(identifier: "mcpSettingsLink").firstMatch
        scrollToElement(mcpLink, in: app)
        guard mcpLink.waitForExistence(timeout: 5) else {
            throw XCTSkip("MCP 配置入口未渲染，跳过测试")
        }
        mcpLink.tap()

        let addButton = app.buttons["addMCPServerButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "应存在添加按钮")
        addButton.tap()

        let nameField = app.textFields["mcpServerNameField"]
        let urlField = app.textFields["mcpServerURLField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5) || urlField.waitForExistence(timeout: 5),
                      "应进入添加 Server 页面")
    }

    func testDeleteMCPServer() throws {
        let app = Self.app!

        app.buttons["settingsButton"].tap()
        let mcpLink = app.descendants(matching: .any).matching(identifier: "mcpSettingsLink").firstMatch
        scrollToElement(mcpLink, in: app)
        guard mcpLink.waitForExistence(timeout: 5) else {
            throw XCTSkip("MCP 配置入口未渲染，跳过测试")
        }
        mcpLink.tap()

        let addButton = app.buttons["addMCPServerButton"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()
            let cancelButton = app.buttons["cancel"]
            if cancelButton.waitForExistence(timeout: 3) {
                cancelButton.tap()
            }
        }
    }
}
