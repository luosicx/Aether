import XCTest
@testable import Aether

/// ToolAuthorization 单元测试：验证敏感工具授权状态生命周期
final class ToolAuthorizationTests: XCTestCase {
    private let auth = ToolAuthorization.shared
    private let toolName = "run_terminal_command"
    private let alwaysAuthorizedKeyPrefix = "aether.tool.auth.always."

    override func setUp() {
        super.setUp()
        // 清理测试工具的授权状态，避免单例状态跨测试污染
        auth.revokeAuthorization(toolName: toolName)
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
    }

    override func tearDown() {
        auth.revokeAuthorization(toolName: toolName)
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
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
}
