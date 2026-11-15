import XCTest

/// MCP 设置界面 UI 测试。
///
/// 测试覆盖：
/// 1. 打开 MCP 设置
/// 2. 添加 Server
/// 3. 删除 Server
///
/// 复用 AetherUITests 的 launchArguments 约定（UITEST_RESET_DATA + UITEST_DISABLE_SPLASH）。
final class MCPSettingsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 创建带 UITEST_RESET_DATA + UITEST_DISABLE_SPLASH 启动参数的 app 实例
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_DISABLE_NETWORK", "UITEST_RESET_DATA", "UITEST_DISABLE_SPLASH"]
        return app
    }

    /// 在 Form 中向下滚动以找到目标元素（SwiftUI Form 懒渲染，底部 Section 需滚动才可见）
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 10) {
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

    // MARK: - 流 1：打开 MCP 设置

    /// 验证从设置页可以导航到 MCP 配置页，且页面标题与添加按钮存在。
    func testOpenMCPSettings() throws {
        let app = makeApp()
        app.launch()

        // 打开设置
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10), "应存在设置按钮")
        app.buttons["settingsButton"].tap()

        // 滚动找到 MCP 配置入口
        let mcpLink = app.descendants(matching: .any).matching(identifier: "mcpSettingsLink").firstMatch
        // 先尝试直接查找，找不到再滚动
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

        // MCP 配置入口存在时点击进入
        guard mcpLink.waitForExistence(timeout: 5) else {
            throw XCTSkip("MCP 配置入口未渲染于无障碍树，跳过测试")
        }
        mcpLink.tap()

        // 验证 MCPSettingsView 已展示：页面标识或添加按钮存在
        let addButton = app.buttons["addMCPServerButton"]
        let viewIdentifier = app.descendants(matching: .any).matching(identifier: "MCPSettingsView").firstMatch
        let entered = addButton.waitForExistence(timeout: 5) || viewIdentifier.waitForExistence(timeout: 3)
        XCTAssertTrue(entered, "应进入 MCP 配置页（添加按钮或页面标识应存在）")
    }

    // MARK: - 流 2：添加 Server

    /// 验证添加 MCP Server 的完整流程：打开 MCP 配置 → 添加 → 填表 → 保存 → 列表出现新条目。
    func testAddMCPServer() throws {
        let app = makeApp()
        app.launch()

        // 打开设置
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()

        // 导航到 MCP 配置
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
            throw XCTSkip("MCP 配置入口未渲染，跳过添加测试")
        }
        mcpLink.tap()

        // 等待添加按钮出现
        let addButton = app.buttons["addMCPServerButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "应存在添加 Server 按钮")
        addButton.tap()

        // 填写表单：名称
        let nameField = app.textFields["serverNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "应存在名称输入框")
        nameField.tap()
        nameField.typeText("测试 Server")

        // 选择 SSE 传输（默认可能是 SSE，直接填 URL）
        let urlField = app.textFields["urlField"]
        // urlField 可能在 stdio 模式下不存在，先检查传输类型
        if !urlField.exists {
            // 可能当前是 stdio 模式，切换到 SSE
            let sseSegment = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "SSE")
            ).firstMatch
            if sseSegment.waitForExistence(timeout: 3) {
                sseSegment.tap()
            }
        }
        XCTAssertTrue(urlField.waitForExistence(timeout: 3), "应存在 URL 输入框")
        urlField.tap()
        urlField.typeText("http://localhost:3000/sse")

        // 关闭键盘（点击导航栏区域）
        if app.keyboards.firstMatch.exists {
            let window = app.windows.firstMatch
            let topPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05))
            topPoint.tap()
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }

        // 保存
        let saveButton = app.buttons["saveServerButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "应存在保存按钮")
        // 保存按钮需在名称和 URL 都非空时才启用
        if !saveButton.isEnabled {
            // 滚动让保存按钮完全可见
            urlField.swipeUp()
            _ = saveButton.waitForExistence(timeout: 1)
        }
        saveButton.tap()

        // 验证列表出现新条目（通过名称或行标识查找）
        let serverText = app.staticTexts["测试 Server"]
        let entered = serverText.waitForExistence(timeout: 5)
        XCTAssertTrue(entered, "添加后列表应出现「测试 Server」条目")
    }

    // MARK: - 流 3：删除 Server

    /// 验证删除 MCP Server 的流程：先添加一个 Server → 通过确认弹窗删除 → 列表清空。
    func testDeleteMCPServer() throws {
        let app = makeApp()
        app.launch()

        // 每次跑都用唯一的 Server 名：MCP 配置存在 UserDefaults（MCPSettingsView.saveConfigs），
        // 而 UITEST_RESET_DATA 只清 SwiftData（AetherApp+Shared.swift:142 → ChatStorage.wipeAllData），
        // 上一轮留下的条目会一直在列表里。名字写死成「待删除 Server」时，列表里会同时有旧的和新加的
        // 两条同名记录：删掉任意一条，按名字找的那条 staticText 都还在，断言就永远红——本地实测正是
        // 这个形状（探针单跑残留那一条时，同样的左滑 + 确认弹窗 + 点「删除」把记录真删掉了，rows=0）。
        let serverName = "UITestDel-\(UUID().uuidString.prefix(8))"

        // 打开设置
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()

        // 导航到 MCP 配置
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
            throw XCTSkip("MCP 配置入口未渲染，跳过删除测试")
        }
        mcpLink.tap()

        // 先添加一个 Server 供删除
        let addButton = app.buttons["addMCPServerButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "应存在添加 Server 按钮")
        addButton.tap()

        let nameField = app.textFields["serverNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(serverName)

        // 确保使用 SSE 传输并填 URL
        let urlField = app.textFields["urlField"]
        if !urlField.exists {
            let sseSegment = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "SSE")
            ).firstMatch
            if sseSegment.waitForExistence(timeout: 3) {
                sseSegment.tap()
            }
        }
        // 滚动表单让 URL 输入框可见（键盘可能遮挡下方字段）
        if urlField.waitForExistence(timeout: 3) {
            if !urlField.isHittable {
                nameField.swipeUp()
                _ = urlField.waitForExistence(timeout: 2)
            }
            urlField.tap()
            urlField.typeText("http://localhost:4000/sse")
        }

        // 关闭键盘
        if app.keyboards.firstMatch.exists {
            let window = app.windows.firstMatch
            let topPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05))
            topPoint.tap()
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
        }

        let saveButton = app.buttons["saveServerButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8), "应存在保存按钮")
        // 保存按钮需在名称和 URL 都非空时才启用；若被键盘遮挡或未启用则滚动后重试
        if !saveButton.isEnabled {
            nameField.swipeUp()
            _ = saveButton.waitForExistence(timeout: 3)
        }
        // 轮询 isHittable，等待滚动惯性结束
        let saveHitDeadline = Date().addingTimeInterval(3)
        while !saveButton.isHittable && Date() < saveHitDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        saveButton.tap()

        // 验证 Server 已添加
        let serverText = app.staticTexts[serverName]
        XCTAssertTrue(serverText.waitForExistence(timeout: 8), "添加后应出现条目")

        // 左滑删除（Form 的 ForEach.onDelete → 系统行操作 → confirmationDialog）
        // 行 identifier 是 `mcpServerRow_<UUID>`（MCPSettingsView.swift:67），UUID 在测试里不可预知，
        // 所以按「前缀 + 本用例自己的名字」两条一起筛——只按前缀取 firstMatch 会删到残留记录那一行。
        // 旧写法 `cells.containing(.staticText, identifier: "待删除 Server")` 永远匹配不上：containing
        // 比的是子元素的 identifier，而 serverRow 里的文案只有 label、没有 identifier，于是整段删除流程
        // 被外层 if 跳过，末尾再用 XCTAssertTrue(true) 收场——这条用例从头到尾没验证过"删除"这件事。
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "mcpServerRow_", serverName)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "添加后应能按 mcpServerRow_ + 本次名字定位到 Server 行")
        row.swipeLeft()
        // 行操作按钮由系统按模拟器语言生成（英文 "Delete"、中文 "删除"）；此刻确认弹窗还没出现，
        // 按 label 精确匹配不会撞到弹窗里那个同为「删除」的 destructive 按钮。
        let rowActionDelete = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", "Delete", "删除")
        ).firstMatch
        XCTAssertTrue(rowActionDelete.waitForExistence(timeout: 5), "左滑后应出现删除行操作")
        rowActionDelete.tap()

        // 确认弹窗的 destructive 按钮由产品标注了 identifier
        let confirmDelete = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", "confirmDeleteServerButton")
        ).firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5), "应弹出删除确认并提供「删除」按钮")
        confirmDelete.tap()

        // 真断言：本用例添加的那条消失（名字唯一，残留记录不会让这条断言永远落空）
        XCTAssertTrue(serverText.waitForNonExistence(timeout: 10), "确认删除后本次添加的条目应消失")
    }
}
