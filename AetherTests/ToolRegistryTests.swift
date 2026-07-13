import XCTest
@testable import Aether

/// ToolRegistry 单元测试
@MainActor
final class ToolRegistryTests: XCTestCase {
    private let registry = ToolRegistry.shared
    private let disabledTools = [
        "run_terminal_command",
        "run_applescript",
        "control_safari",
        "create_shortcut",
        "simulate_input"
    ]
    private var originalEnabledStates: [String: Bool] = [:]

    override func setUp() {
        super.setUp()
        // 保存所有已注册工具的原始启用状态，便于 tearDown 恢复
        originalEnabledStates = Dictionary(
            uniqueKeysWithValues: registry.allToolDefs.map { ($0.function.name, registry.isEnabled(name: $0.function.name)) }
        )
        // 清理持久化记录并按默认值重置：高危工具关闭，其余开启
        for name in registry.allToolDefs.map(\.function.name) {
            UserDefaults.standard.removeObject(forKey: "aether.tool.enabled.\(name)")
            registry.setEnabled(name: name, value: !disabledTools.contains(name))
        }
    }

    override func tearDown() {
        // 恢复原始启用状态
        for (name, value) in originalEnabledStates {
            registry.setEnabled(name: name, value: value)
        }
        super.tearDown()
    }

    // MARK: - 安全相关测试

    /// 默认 `enabledTools` 不应包含高危 macOS 工具
    func testDefaultDisabledToolsAreNotEnabled() {
        for name in disabledTools {
            XCTAssertFalse(registry.isEnabled(name: name), "\(name) 默认应被禁用")
        }
    }

    /// `setEnabled(name:value:)` 后 `isEnabled(name:)` 返回 true
    func testSetEnabledMakesToolEnabled() {
        let name = "calculate"
        registry.setEnabled(name: name, value: true)
        XCTAssertTrue(registry.isEnabled(name: name), "setEnabled true 后工具应被启用")
    }

    /// `availableTools()` 在启用前后发生变化
    func testAvailableToolsChangesAfterEnabling() {
        let name = "calculate"
        // 先确保关闭
        registry.setEnabled(name: name, value: false)
        let disabledCount = registry.availableTools().count
        XCTAssertFalse(registry.availableTools().contains(where: { $0.name == name }))

        registry.setEnabled(name: name, value: true)
        let enabledCount = registry.availableTools().count
        XCTAssertEqual(enabledCount, disabledCount + 1, "启用后可用工具数应增加 1")
        XCTAssertTrue(registry.availableTools().contains(where: { $0.name == name }))
    }

    /// `requiresAuthorization(name:)` 对敏感工具返回 true，对普通工具返回 false
    func testRequiresAuthorizationForSensitiveTools() {
        XCTAssertTrue(registry.requiresAuthorization(name: "read_clipboard"), "read_clipboard 应需授权")
        XCTAssertTrue(registry.requiresAuthorization(name: "run_terminal_command"), "run_terminal_command 应需授权")
        XCTAssertTrue(registry.requiresAuthorization(name: "control_safari"), "control_safari 应需授权（匹配子操作）")
        XCTAssertTrue(registry.requiresAuthorization(name: "control_safari.run_js"), "control_safari.run_js 应需授权")
        XCTAssertFalse(registry.requiresAuthorization(name: "calculate"), "calculate 不应需授权")
        XCTAssertFalse(registry.requiresAuthorization(name: "get_current_time"), "get_current_time 不应需授权")
    }

    /// 新增敏感工具 manage_file/manage_window/simulate_input 应需授权
    func testNewSensitiveToolsRequireAuthorization() {
        XCTAssertTrue(registry.requiresAuthorization(name: "manage_file"), "manage_file 应需授权")
        XCTAssertTrue(registry.requiresAuthorization(name: "manage_window"), "manage_window 应需授权")
        XCTAssertTrue(registry.requiresAuthorization(name: "simulate_input"), "simulate_input 应需授权")
    }

    /// simulate_input 应在默认禁用列表中
    func testSimulateInputDefaultDisabled() {
        XCTAssertFalse(registry.isEnabled(name: "simulate_input"), "simulate_input 默认应被禁用")
    }

    /// `execute(name:arguments:)` 对未启用工具抛出错误（domain = ToolRegistry，code = 3）
    func testExecuteDisabledToolThrowsNotEnabled() async {
        let name = "calculate"
        registry.setEnabled(name: name, value: false)
        do {
            _ = try await registry.execute(name: name, arguments: [:])
            XCTFail("未启用工具应抛错")
        } catch {
            let nserror = error as NSError
            XCTAssertEqual(nserror.domain, "ToolRegistry", "错误 domain 应为 ToolRegistry")
            XCTAssertEqual(nserror.code, 3, "未启用工具错误 code 应为 3")
        }
    }

    /// register 同名工具应覆盖：getTool 返回新工具
    func testRegisterOverridesSameName() async throws {
        defer { registry.register(tool: CalculatorTool()) } // 恢复默认工具
        registry.register(tool: DummyTool(name: "calculate", result: "OVERRIDE"))
        let tool = registry.getTool(named: "calculate")
        XCTAssertNotNil(tool, "覆盖后应能取到工具")
        let result = try await tool!.execute(arguments: [:])
        XCTAssertEqual(result, "OVERRIDE", "同名注册应返回新工具")
    }

    /// getTool("calculate") 应返回非 nil
    func testGetToolFound() {
        XCTAssertNotNil(registry.getTool(named: "calculate"), "已注册的 calculate 工具应可取到")
    }

    /// getTool("non_existent") 应返回 nil
    func testGetToolNotFoundReturnsNil() {
        XCTAssertNil(registry.getTool(named: "non_existent"), "未注册的工具应返回 nil")
    }

    /// execute 未注册工具应抛 NSError（domain = "ToolRegistry"，code = 1）
    func testExecuteNotRegisteredThrowsNSError() async {
        do {
            _ = try await registry.execute(name: "non_existent", arguments: [:])
            XCTFail("未注册工具应抛错")
        } catch {
            let nserror = error as NSError
            XCTAssertEqual(nserror.domain, "ToolRegistry", "错误 domain 应为 ToolRegistry")
            XCTAssertEqual(nserror.code, 1, "错误 code 应为 1")
        }
    }

    /// init 后 allToolDefs 应含正确数量的工具（跨平台 14 个，macOS 额外 11 个共 25 个）
    func testAllToolDefsCount() {
        #if os(macOS)
        let expected = 25
        #else
        let expected = 14
        #endif
        XCTAssertEqual(registry.allToolDefs.count, expected,
                       "默认应注册 \(expected) 个工具")
    }

    /// ToolDef 应可序列化为 JSON，且 JSON 含 "name" 与 "parameters" 字段
    func testToolDefSerialization() throws {
        guard let def = registry.allToolDefs.first else {
            return XCTFail("allToolDefs 不应为空")
        }
        let data = try JSONEncoder().encode(def)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"name\""), "JSON 应含 name 字段")
        XCTAssertTrue(json.contains("\"parameters\""), "JSON 应含 parameters 字段")
    }
}

/// 测试用占位工具：name 与 result 可配置，execute 返回固定字符串
private final class DummyTool: ToolProtocol {
    private let name: String
    private let result: String

    init(name: String, result: String) {
        self.name = name
        self.result = result
    }

    var definition: ToolDefinition {
        ToolDefinition(name: name, description: "test dummy", parameters: [:])
    }

    func execute(arguments: [String: Any]) async throws -> String {
        result
    }
}
