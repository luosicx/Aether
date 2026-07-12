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
}
