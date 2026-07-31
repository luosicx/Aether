#if os(visionOS)
import XCTest
import SwiftUI
@testable import Aether

/// v2.0 visionOS 空间对话界面与工具注册测试。
///
/// 覆盖：
/// - SpatialChatView 基本属性与实例化
/// - SpatialMessageBubble 基本属性与实例化
/// - ToolRegistry+visionOS 注册的空间化工具数量与定义
@MainActor
final class SpatialChatViewTests: XCTestCase {
    private let registry = ToolRegistry.shared

    // MARK: - SpatialChatView 基本属性

    /// SpatialChatView 标记为骨架（isSkeleton == true），表明当前未接入 RealityKit 3D 渲染
    func testSpatialChatViewIsSkeleton() {
        XCTAssertTrue(SpatialChatView.isSkeleton, "当前为骨架实现，isSkeleton 应为 true")
    }

    /// SpatialChatView 可用 ChatViewModel 实例化（编译期结构验证 + 不崩溃）
    func testSpatialChatViewCanBeInstantiated() {
        let viewModel = ChatViewModel()
        let view = SpatialChatView(viewModel: viewModel)
        XCTAssertTrue(type(of: view) == SpatialChatView.self, "SpatialChatView 应可实例化")
    }

    // MARK: - SpatialMessageBubble 基本属性

    /// SpatialMessageBubble 可用 ChatMessage 实例化（不同角色均应可构造）
    func testSpatialMessageBubbleCanBeInstantiatedForAllRoles() {
        let userMessage = ChatMessage(role: "user", content: "你好")
        let assistantMessage = ChatMessage(role: "assistant", content: "我是 Aether")
        let userBubble = SpatialMessageBubble(message: userMessage)
        let assistantBubble = SpatialMessageBubble(message: assistantMessage)
        XCTAssertTrue(type(of: userBubble) == SpatialMessageBubble.self, "user 气泡应可实例化")
        XCTAssertTrue(type(of: assistantBubble) == SpatialMessageBubble.self, "assistant 气泡应可实例化")
    }

    // MARK: - ToolRegistry+visionOS 工具注册

    /// registerVisionOSTools 应在调用后新增 3 个空间化工具
    func testRegisterVisionOSToolsAddsThreeTools() {
        // 先移除确保未注册，记录基线
        for name in ToolRegistry.visionOSToolNames {
            registry.unregister(name: name)
        }
        let countBefore = registry.toolCount

        registry.registerVisionOSTools()

        XCTAssertEqual(registry.toolCount, countBefore + 3,
                       "registerVisionOSTools 应新增 3 个空间化工具")
    }

    /// 3 个空间化工具名应全部已注册，且可通过 getTool 取到
    func testVisionOSToolNamesRegistered() {
        registry.registerVisionOSTools()
        for name in ToolRegistry.visionOSToolNames {
            XCTAssertNotNil(registry.getTool(named: name), "\(name) 应已注册")
            XCTAssertTrue(registry.getToolNames().contains(name), "getToolNames 应包含 \(name)")
        }
    }

    /// macOS 独有工具不应在 visionOS 注册
    func testMacOSOnlyToolsNotRegistered() {
        let macOnlyNames = [
            "run_applescript",
            "take_screenshot",
            "extract_text_from_image",
            "run_terminal_command",
            "manage_window",
            "manage_file",
            "control_safari",
            "simulate_input"
        ]
        let registered = Set(registry.getToolNames())
        for name in macOnlyNames {
            XCTAssertFalse(registered.contains(name), "macOS 独有工具 \(name) 不应在 visionOS 注册")
        }
    }

    /// 空间化工具定义应含非空 name 与 description
    func testSpatialToolDefinitionsHaveNameAndDescription() {
        registry.registerVisionOSTools()
        for name in ToolRegistry.visionOSToolNames {
            guard let tool = registry.getTool(named: name) else {
                return XCTFail("\(name) 应已注册")
            }
            XCTAssertEqual(tool.definition.name, name, "工具名应与集合中的键一致")
            XCTAssertFalse(tool.definition.description.isEmpty, "\(name) 描述不应为空")
        }
    }

    /// registerVisionOSTools 应可重复调用且幂等（不重复增加数量）
    func testRegisterVisionOSToolsIsIdempotent() {
        registry.registerVisionOSTools()
        let countAfterFirst = registry.toolCount
        registry.registerVisionOSTools()
        XCTAssertEqual(registry.toolCount, countAfterFirst,
                       "重复调用 registerVisionOSTools 应幂等，工具数量不应增加")
    }
}
#endif
