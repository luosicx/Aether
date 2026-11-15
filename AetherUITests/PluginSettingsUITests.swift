import XCTest

/// Task 16.3 UIT：插件设置界面 UI 测试。
///
/// 覆盖流程：
/// 1. 打开设置 → 进入插件管理页
/// 2. 验证空状态提示
/// 3. 安装示例插件 → 验证插件出现
/// 4. 卸载插件 → 验证插件消失
final class PluginSettingsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 创建带测试启动参数的 app 实例
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_DISABLE_NETWORK", "UITEST_RESET_DATA", "UITEST_DISABLE_SPLASH"]
        return app
    }

    /// 在 Form 中向下滚动到目标元素整块进入可视区。
    /// 停止条件不能用 isHittable：元素只露出几 pt 时它也为真，而中心仍在屏外，tap 会落空。
    /// 拖拽要在终点停住再抬手（thenHoldForDuration），抬手速度归零才不会带惯性过冲：
    /// swipeUp 和直接抬手的拖拽都会甩过目标节，而 Form 懒渲染，甩过去就再也找不回来
    /// （CI 实测四条用例 3 次滑动即命中，失败那条滑满 10 次仍未命中）；
    /// 过冲后只能反向拖，而在 Form 顶部反向拖等于 sheet 的下滑关闭手势。
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 10) {
        // 三个候选都要查 .exists：视图切换瞬间可能一个滚动容器都没有，
        // 直接对不存在的 firstMatch 取坐标会抛「Failed to get matching snapshot」。
        func scroller() -> XCUIElement? {
            if app.tables.firstMatch.exists { return app.tables.firstMatch }
            if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
            if app.scrollViews.firstMatch.exists { return app.scrollViews.firstMatch }
            return nil
        }
        func settled(in container: XCUIElement?) -> Bool {
            guard element.exists, element.isHittable else { return false }
            guard let visible = container?.frame else { return true }
            let frame = element.frame
            return frame.minY >= visible.minY && frame.maxY <= visible.maxY
        }
        var attempts = 0
        while attempts < maxAttempts {
            let container = scroller()
            if settled(in: container) { return }
            if let container {
                let from = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                let to = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.3)
            }
            attempts += 1
            _ = element.waitForExistence(timeout: 1)
        }
    }



    // MARK: - 流 1：进入插件管理页

    /// 打开设置 → 点击插件管理 → 验证插件管理页出现
    func testNavigateToPluginSettings() {
        let app = makeApp()
        app.launch()

        // 打开设置
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()

        // 滚动找到插件管理链接
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        XCTAssertTrue(pluginLink.waitForExistence(timeout: 5), "应存在插件管理入口")

        // 点击进入插件管理页
        pluginLink.tap()
        XCTAssertTrue(app.navigationBars["插件管理"].waitForExistence(timeout: 5),
                      "应进入插件管理页面")
    }

    // MARK: - 流 2：空状态显示

    /// 进入插件管理页后应显示空状态提示
    func testPluginSettingsShowsEmptyState() {
        let app = makeApp()
        app.launch()

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        pluginLink.tap()

        XCTAssertTrue(app.navigationBars["插件管理"].waitForExistence(timeout: 5))
        // 空状态文案
        let emptyState = app.staticTexts["pluginEmptyState"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5), "应显示空状态提示")
    }

    // MARK: - 流 3：安装示例插件

    /// 点击安装示例插件 → 验证插件出现在列表中
    func testInstallSamplePlugin() {
        let app = makeApp()
        app.launch()

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        pluginLink.tap()

        XCTAssertTrue(app.navigationBars["插件管理"].waitForExistence(timeout: 5))

        // 点击安装示例插件
        let installButton = app.buttons["installSamplePluginButton"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 5), "应存在安装按钮")
        installButton.tap()

        // 验证插件行出现（插件行 identifier 以 pluginRow_ 开头）
        let pluginRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pluginRow_")
        ).firstMatch
        XCTAssertTrue(pluginRow.waitForExistence(timeout: 5), "安装后应出现插件行")

        // 验证插件名称显示
        XCTAssertTrue(app.staticTexts["示例插件"].waitForExistence(timeout: 3),
                      "应显示示例插件名称")
    }

    // MARK: - 流 4：卸载插件

    /// 安装插件后点击卸载 → 验证插件从列表消失
    func testUninstallPlugin() {
        let app = makeApp()
        app.launch()

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        pluginLink.tap()

        XCTAssertTrue(app.navigationBars["插件管理"].waitForExistence(timeout: 5))

        // 先安装
        let installButton = app.buttons["installSamplePluginButton"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 5))
        installButton.tap()

        // 等待插件行出现
        let pluginRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pluginRow_")
        ).firstMatch
        XCTAssertTrue(pluginRow.waitForExistence(timeout: 5), "安装后应出现插件行")

        // 点击卸载按钮（identifier 以 uninstallPluginButton_ 开头）
        let uninstallButton = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "uninstallPluginButton_")
        ).firstMatch
        XCTAssertTrue(uninstallButton.waitForExistence(timeout: 3), "应存在卸载按钮")
        uninstallButton.tap()

        // 验证插件行消失
        _ = pluginRow.waitForNonExistence(timeout: 5)
        XCTAssertFalse(pluginRow.exists, "卸载后插件行应消失")
    }

    // MARK: - 流 5：权限查看

    /// 安装插件后展开权限查看 → 验证权限信息显示
    func testViewPluginPermissions() {
        let app = makeApp()
        app.launch()

        app.buttons["settingsButton"].tap()
        let pluginLink = app.descendants(matching: .any).matching(identifier: "pluginManagementLink").firstMatch
        scrollToElement(pluginLink, in: app)
        XCTAssertTrue(pluginLink.waitForExistence(timeout: 5), "应存在插件管理入口")
        pluginLink.tap()

        XCTAssertTrue(app.navigationBars["插件管理"].waitForExistence(timeout: 5))

        // 安装插件
        let installButton = app.buttons["installSamplePluginButton"]
        installButton.tap()

        // 等待插件行出现
        let pluginRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pluginRow_")
        ).firstMatch
        XCTAssertTrue(pluginRow.waitForExistence(timeout: 8))

        // 点击权限 DisclosureGroup 展开
        let disclosure = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pluginPermissionsDisclosure_")
        ).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 8), "应存在权限查看控件")
        disclosure.tap()

        // 验证权限行出现（network 权限）——CI 模拟器 DisclosureGroup 展开动画存在延迟，
        // 增加超时 + 重试点击 disclosure，并提供 label 兜底匹配
        let networkPerm = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier CONTAINS %@", "network")
        ).firstMatch
        let networkLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "网络访问")
        ).firstMatch

        var permAppeared = networkPerm.waitForExistence(timeout: 8)
            || networkLabel.waitForExistence(timeout: 3)

        // 重试：DisclosureGroup 在部分模拟器版本上首次点击可能未展开，再次点击后等待
        if !permAppeared {
            if disclosure.exists { disclosure.tap() }
            permAppeared = networkPerm.waitForExistence(timeout: 8)
                || networkLabel.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(permAppeared, "展开后应显示网络权限行")
    }
}
