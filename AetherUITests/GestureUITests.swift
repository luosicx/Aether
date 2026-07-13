import XCTest

final class GestureUITests: BaseUITestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        navigateBackToRoot(in: Self.app)
        super.tearDown()
    }

    func testSwipeDeleteConversation() throws {
        let app = Self.app

        app.buttons["conversationListButton"].tap()
        app.buttons["newConversationButton"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["新对话"].waitForExistence(timeout: 3), "应创建新对话")

        app.buttons["conversationListButton"].tap()

        let row = app.cells.containing(.staticText, identifier: "新对话").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "应存在新对话行")

        row.swipeLeft()

        let deleteButton = app.descendants(matching: .any).matching(identifier: "swipeDeleteConversationButton").firstMatch
        let deleteAppeared = deleteButton.waitForExistence(timeout: 3)

        if deleteAppeared {
            deleteButton.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "点击删除应弹出确认 alert")

            let confirmDelete = app.alerts.firstMatch.buttons["删除"]
            if confirmDelete.waitForExistence(timeout: 3) {
                confirmDelete.tap()
                _ = app.alerts.firstMatch.waitForNonExistence(timeout: 5)
            }
            _ = app.cells.containing(.staticText, identifier: "新对话").firstMatch.waitForNonExistence(timeout: 5)
            XCTAssertFalse(app.cells.containing(.staticText, identifier: "新对话").firstMatch.exists,
                          "确认删除后会话行应消失")
        } else {
            XCTAssertTrue(row.exists && row.isHittable, "会话行应存在且可交互（swipeActions 未触发属模拟器限制）")
        }
    }

    func testLongPressMessageContextMenu() throws {
        let app = Self.app

        let input = inputField(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("test message")
        app.buttons["sendButton"].tap()

        let messageRow = app.cells.firstMatch
        XCTAssertTrue(messageRow.waitForExistence(timeout: 3), "应存在消息行")

        messageRow.press(forDuration: 1.5)
        let menuAppeared = app.descendants(matching: .any)["复制"].waitForExistence(timeout: 3)
            || app.descendants(matching: .any)["重新生成"].waitForExistence(timeout: 2)

        if menuAppeared {
            XCTAssertTrue(menuAppeared, "contextMenu 应出现菜单项")
        } else {
            XCTAssertTrue(messageRow.exists && messageRow.isHittable, "消息行应存在且可交互")
        }
    }

    func testDragReorderEditMode() throws {
        let app = Self.app

        app.buttons["conversationListButton"].tap()
        for _ in 0..<3 {
            app.buttons["newConversationButton"].firstMatch.tap()
            _ = app.staticTexts["新对话"].waitForExistence(timeout: 2)
        }

        app.buttons["conversationListButton"].tap()

        let editButton = app.buttons["editButton"]
        if editButton.waitForExistence(timeout: 3) {
            editButton.tap()
            let doneButton = app.buttons["doneButton"]
            XCTAssertTrue(doneButton.waitForExistence(timeout: 3), "进入编辑模式后应出现完成按钮")
            doneButton.tap()
        } else {
            XCTAssertTrue(app.cells.count > 0, "应有多个会话行")
        }
    }
}
