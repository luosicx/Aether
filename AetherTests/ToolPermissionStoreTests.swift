import XCTest
@testable import Aether

/// ToolPermissionStore 单元测试
@MainActor
final class ToolPermissionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ToolPermissionStore!
    private let suiteName = "ToolPermissionStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = ToolPermissionStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    /// 高危工具默认禁用
    func testHighRiskToolsDisabledByDefault() {
        XCTAssertFalse(store.isEnabled(.runTerminalCommand), "终端命令工具应默认禁用")
        XCTAssertFalse(store.isEnabled(.runAppleScript), "AppleScript 工具应默认禁用")
        XCTAssertFalse(store.isEnabled(.controlSafari), "Safari 控制工具应默认禁用")
        XCTAssertFalse(store.isEnabled(.simulateInput), "输入自动化工具应默认禁用")
        XCTAssertFalse(store.isEnabled(.manageFile), "文件操作工具应默认禁用")
    }

    /// 安全工具默认启用
    func testSafeToolsEnabledByDefault() {
        XCTAssertTrue(store.isEnabled(.getCurrentTime), "时间工具应默认启用")
        XCTAssertTrue(store.isEnabled(.calculate), "计算器工具应默认启用")
        XCTAssertTrue(store.isEnabled(.getWeather), "天气工具应默认启用")
        XCTAssertTrue(store.isEnabled(.createAlarm), "闹钟工具应默认启用")
        XCTAssertTrue(store.isEnabled(.writeClipboard), "写入剪贴板工具应默认启用")
    }

    /// 敏感工具默认启用（但执行前需确认）
    func testSensitiveToolsEnabledByDefault() {
        XCTAssertTrue(store.isEnabled(.readClipboard), "读取剪贴板应默认启用")
        XCTAssertTrue(store.isEnabled(.searchContacts), "通讯录搜索应默认启用")
        XCTAssertTrue(store.isEnabled(.getLocation), "定位应默认启用")
        XCTAssertTrue(store.isEnabled(.takeScreenshot), "截图应默认启用")
        XCTAssertTrue(store.isEnabled(.extractTextFromImage), "OCR 应默认启用")
    }

    /// 启用高危工具后应可读取为启用
    func testEnableHighRiskTool() {
        store.setEnabled(true, for: .runTerminalCommand)
        XCTAssertTrue(store.isEnabled(.runTerminalCommand))
        XCTAssertTrue(store.isEnabled("run_terminal_command"))
    }

    /// 禁用安全工具后应读取为禁用
    func testDisableSafeTool() {
        store.setEnabled(false, for: .calculate)
        XCTAssertFalse(store.isEnabled(.calculate))
    }

    /// resetToDefaults 后恢复默认状态
    func testResetToDefaults() {
        store.setEnabled(true, for: .runTerminalCommand)
        store.setEnabled(false, for: .calculate)
        store.resetToDefaults()
        XCTAssertFalse(store.isEnabled(.runTerminalCommand), "reset 后高危工具应禁用")
        XCTAssertTrue(store.isEnabled(.calculate), "reset 后安全工具应启用")
    }

    /// 未知工具默认启用
    func testUnknownToolDefaultsToEnabled() {
        XCTAssertTrue(store.isEnabled("unknown_tool"), "未知工具应默认启用")
    }

    /// clearAll 后默认键也被清除，未知工具仍默认启用
    func testClearAll() {
        store.setEnabled(true, for: .runTerminalCommand)
        store.setEnabled(false, for: .calculate)
        store.clearAll()
        XCTAssertTrue(store.isEnabled("unknown_tool"))
        XCTAssertFalse(store.isEnabled(.runTerminalCommand), "clearAll 后高危工具应恢复默认禁用")
        XCTAssertTrue(store.isEnabled(.calculate), "clearAll 后安全工具应恢复默认启用")
    }
}
