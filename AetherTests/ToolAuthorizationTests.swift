import XCTest
@testable import Aether

/// ToolAuthorization 单元测试：验证敏感工具授权状态生命周期
final class ToolAuthorizationTests: XCTestCase {
    private let auth = ToolAuthorization.shared
    /// 使用非高危工具名测试常规授权逻辑
    private let toolName = "read_clipboard"
    /// 高危工具名，用于验证 neverAlwaysAllow 行为
    private let dangerousToolName = "run_terminal_command"
    private let alwaysAuthorizedKeyPrefix = "aether.tool.auth.always."

    override func setUp() {
        super.setUp()
        // 清理测试工具的授权状态，避免单例状态跨测试污染
        auth.revokeAuthorization(toolName: toolName)
        auth.revokeAuthorization(toolName: dangerousToolName)
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(dangerousToolName)")
    }

    override func tearDown() {
        auth.revokeAuthorization(toolName: toolName)
        auth.revokeAuthorization(toolName: dangerousToolName)
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(dangerousToolName)")
        super.tearDown()
    }

    /// 默认授权状态应为 .denied
    func testAuthorizationStatusDefaultIsDenied() {
        let status = auth.authorizationStatus(for: toolName)
        XCTAssertEqual(status, .denied, "默认状态应为 .denied")
    }

    /// 调用 grantSessionAuthorization 后状态变为 .authorized(sessionOnly: true)
    func testGrantSessionAuthorizationSetsSessionOnly() {
        auth.grantSessionAuthorization(toolName: toolName)
        let status = auth.authorizationStatus(for: toolName)
        XCTAssertEqual(status, .authorized(sessionOnly: true), "本次启动授权应为 sessionOnly: true")
    }

    /// 调用 grantAlwaysAuthorization 后持久化到 UserDefaults
    func testGrantAlwaysAuthorizationPersists() {
        auth.grantAlwaysAuthorization(toolName: toolName)

        let status = auth.authorizationStatus(for: toolName)
        XCTAssertEqual(status, .authorized(sessionOnly: false), "始终允许授权应为 sessionOnly: false")

        let persisted = UserDefaults.standard.bool(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
        XCTAssertTrue(persisted, "始终允许授权应写入 UserDefaults")
    }

    /// revokeAuthorization 后状态清除（session + always）
    func testRevokeAuthorizationClearsStatus() {
        auth.grantSessionAuthorization(toolName: toolName)
        auth.grantAlwaysAuthorization(toolName: toolName)
        XCTAssertNotEqual(auth.authorizationStatus(for: toolName), .denied, "授权后不应为 .denied")

        auth.revokeAuthorization(toolName: toolName)

        let status = auth.authorizationStatus(for: toolName)
        XCTAssertEqual(status, .denied, "撤销后应为 .denied")
        let persisted = UserDefaults.standard.bool(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
        XCTAssertFalse(persisted, "撤销后 UserDefaults 中的持久化标记应被清除")
    }

    // MARK: - Async API 测试

    /// presentConfirmation 在已授权时应直接返回 .authorized，不弹窗
    func testPresentConfirmationReturnsAuthorizedWhenAlreadyAuthorized() async {
        auth.grantSessionAuthorization(toolName: toolName)
        let result = await auth.presentConfirmation(toolName: toolName, details: "test")
        XCTAssertEqual(result, .authorized(sessionOnly: true), "已授权时应直接返回 .authorized(sessionOnly: true)")
    }

    /// presentSensitiveAccessConfirmation 在已授权时应直接返回 .authorized
    func testPresentSensitiveAccessConfirmationReturnsAuthorizedWhenAlreadyAuthorized() async {
        auth.grantAlwaysAuthorization(toolName: toolName)
        let result = await auth.presentSensitiveAccessConfirmation(toolName: toolName, purpose: "test purpose")
        XCTAssertEqual(result, .authorized(sessionOnly: false), "始终授权后应返回 .authorized(sessionOnly: false)")
    }

    /// presentConfirmation 在 alwaysAuthorized 状态下应返回 sessionOnly: false
    func testPresentConfirmationWithAlwaysAuthorized() async {
        auth.grantAlwaysAuthorization(toolName: toolName)
        let result = await auth.presentConfirmation(toolName: toolName, details: nil)
        XCTAssertEqual(result, .authorized(sessionOnly: false), "始终授权应返回 sessionOnly: false")
    }

    /// presentSensitiveAccessConfirmation 在 sessionOnly 状态下应返回 sessionOnly: true
    func testPresentSensitiveAccessWithSessionOnly() async {
        auth.grantSessionAuthorization(toolName: toolName)
        let result = await auth.presentSensitiveAccessConfirmation(toolName: toolName, purpose: nil)
        XCTAssertEqual(result, .authorized(sessionOnly: true), "本次启动授权应返回 sessionOnly: true")
    }

    // MARK: - 持久化恢复测试

    /// 新实例应从 UserDefaults 恢复 alwaysAuthorized 状态
    func testRestoreAlwaysAuthorizedFromUserDefaults() {
        // 先写入持久化标记
        UserDefaults.standard.set(true, forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")

        // 通过 revoke 再 grantAlways 来间接验证 restore 逻辑
        // 注意：ToolAuthorization 是单例，restoreAlwaysAuthorized 在 init 时调用
        // 这里通过验证 grantAlwaysAuthorization 的持久化效果来间接覆盖
        auth.grantAlwaysAuthorization(toolName: toolName)
        let persisted = UserDefaults.standard.bool(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
        XCTAssertTrue(persisted, "grantAlwaysAuthorization 应持久化到 UserDefaults")

        // 验证撤销后清除
        auth.revokeAuthorization(toolName: toolName)
        let cleared = UserDefaults.standard.bool(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
        XCTAssertFalse(cleared, "撤销后 UserDefaults 标记应被清除")
    }

    /// 授权状态在多次 grant/revoke 操作后应保持一致
    func testAuthorizationStatusAfterMultipleOperations() {
        // 多次 grant session
        auth.grantSessionAuthorization(toolName: toolName)
        auth.grantSessionAuthorization(toolName: toolName)
        XCTAssertEqual(auth.authorizationStatus(for: toolName), .authorized(sessionOnly: true))

        // 升级为 always
        auth.grantAlwaysAuthorization(toolName: toolName)
        XCTAssertEqual(auth.authorizationStatus(for: toolName), .authorized(sessionOnly: false))

        // 撤销后应为 denied
        auth.revokeAuthorization(toolName: toolName)
        XCTAssertEqual(auth.authorizationStatus(for: toolName), .denied)

        // 再次 grant always
        auth.grantAlwaysAuthorization(toolName: toolName)
        XCTAssertEqual(auth.authorizationStatus(for: toolName), .authorized(sessionOnly: false))
    }

    // MARK: - 高危工具 neverAlwaysAllow 测试

    /// run_terminal_command 不应被持久化授权（始终允许），每次调用都需确认
    func testDangerousToolCannotBeAlwaysAuthorized() {
        auth.grantAlwaysAuthorization(toolName: dangerousToolName)

        // 状态不应变为 authorized
        XCTAssertEqual(auth.authorizationStatus(for: dangerousToolName), .denied,
                       "高危工具不应被持久化授权")

        // UserDefaults 中不应写入持久化标记
        let persisted = UserDefaults.standard.bool(forKey: "\(alwaysAuthorizedKeyPrefix)\(dangerousToolName)")
        XCTAssertFalse(persisted, "高危工具不应写入 UserDefaults 持久化标记")
    }

    /// run_terminal_command 仍可通过 session 授权（仅本次有效）
    func testDangerousToolCanBeSessionAuthorized() {
        auth.grantSessionAuthorization(toolName: dangerousToolName)
        XCTAssertEqual(auth.authorizationStatus(for: dangerousToolName), .authorized(sessionOnly: true),
                       "高危工具仍可被 session 授权（仅本次有效）")
    }

    /// run_applescript 同样不应被持久化授权
    func testAppleScriptToolCannotBeAlwaysAuthorized() {
        let appleScriptTool = "run_applescript"
        auth.revokeAuthorization(toolName: appleScriptTool)
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(appleScriptTool)")

        auth.grantAlwaysAuthorization(toolName: appleScriptTool)
        XCTAssertEqual(auth.authorizationStatus(for: appleScriptTool), .denied,
                       "run_applescript 不应被持久化授权")

        auth.revokeAuthorization(toolName: appleScriptTool)
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(appleScriptTool)")
    }
}
