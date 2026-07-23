import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// PluginToolRegistryBridge 测试：验证 ToolRegistry 注入与协议遵循。
///
/// 覆盖范围：
/// 1. setup() 将 ToolRegistry.shared 注入 PluginManager.toolRegistry
/// 2. setup() 幂等性（多次调用安全）
/// 3. ToolRegistry 遵循 ToolRegistering 协议
@MainActor
final class PluginToolRegistryBridgeTests: XCTestCase {

    // MARK: - setup 注入

    /// setup() 应将 ToolRegistry.shared 注入到 PluginManager.toolRegistry
    func testSetupInjectsToolRegistryIntoPluginManager() {
        // 先清空确保 setup 是唯一来源
        PluginManager.toolRegistry = nil
        XCTAssertNil(PluginManager.toolRegistry, "前置条件：toolRegistry 应为 nil")

        PluginToolRegistryBridge.setup()

        XCTAssertNotNil(PluginManager.toolRegistry, "setup 后 toolRegistry 应非 nil")
        XCTAssertTrue(PluginManager.toolRegistry === ToolRegistry.shared,
                      "注入的 toolRegistry 应为 ToolRegistry.shared 同一实例")
    }

    /// setup() 多次调用应幂等，不抛错且最终状态一致
    func testSetupIsIdempotent() {
        PluginManager.toolRegistry = nil

        PluginToolRegistryBridge.setup()
        let first = PluginManager.toolRegistry

        // 多次调用不应抛错（setup 非 throwing，这里验证无副作用）
        PluginToolRegistryBridge.setup()
        PluginToolRegistryBridge.setup()

        let afterMultiple = PluginManager.toolRegistry
        XCTAssertNotNil(afterMultiple, "多次 setup 后 toolRegistry 仍应非 nil")
        XCTAssertTrue(first === afterMultiple, "多次 setup 后实例应保持一致（幂等）")
        XCTAssertTrue(afterMultiple === ToolRegistry.shared, "最终应为 ToolRegistry.shared")
    }

    // MARK: - 协议遵循

    /// ToolRegistry.shared 应可作为 ToolRegistering 使用
    func testToolRegistryConformsToToolRegistering() {
        let registry: ToolRegistering = ToolRegistry.shared
        // 能调用协议方法即说明遵循协议
        XCTAssertNotNil(registry.getTool(named: "get_current_time"),
                        "ToolRegistry.shared 应可通过 ToolRegistering 协议查询已注册工具")
    }
}
