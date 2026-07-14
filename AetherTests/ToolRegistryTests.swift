import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
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

    // MARK: - unregister / registerBatch 方法测试

    /// unregister 已注册工具后，getTool 应返回 nil
    func testUnregisterRemovesTool() {
        let name = "calculate"
        XCTAssertNotNil(registry.getTool(named: name), "注销前应能取到工具")
        registry.unregister(name: name)
        XCTAssertNil(registry.getTool(named: name), "注销后应返回 nil")
        // 恢复
        registry.register(tool: CalculatorTool())
    }

    /// unregister 未注册的工具名应不报错（no-op）
    func testUnregisterNonExistentToolIsNoOp() {
        let countBefore = registry.toolCount
        registry.unregister(name: "non_existent_tool")
        XCTAssertEqual(registry.toolCount, countBefore, "注销不存在的工具应为 no-op")
    }

    /// unregister 后 toolCount 应减少 1
    func testUnregisterDecrementsToolCount() {
        let countBefore = registry.toolCount
        registry.unregister(name: "calculate")
        XCTAssertEqual(registry.toolCount, countBefore - 1, "注销后工具数应减 1")
        // 恢复
        registry.register(tool: CalculatorTool())
    }

    /// unregister 后 allToolDefs 不应包含该工具
    func testUnregisterRemovesFromAllToolDefs() {
        registry.unregister(name: "calculate")
        let names = registry.allToolDefs.map { $0.function.name }
        XCTAssertFalse(names.contains("calculate"), "注销后 allToolDefs 不应包含该工具")
        // 恢复
        registry.register(tool: CalculatorTool())
    }

    /// registerBatch 应批量注册多个工具
    func testRegisterBatchRegistersMultipleTools() {
        let dummy1 = DummyTool(name: "batch_tool_1", result: "r1")
        let dummy2 = DummyTool(name: "batch_tool_2", result: "r2")
        registry.registerBatch(tools: [dummy1, dummy2])
        XCTAssertNotNil(registry.getTool(named: "batch_tool_1"), "registerBatch 后应能取到 tool_1")
        XCTAssertNotNil(registry.getTool(named: "batch_tool_2"), "registerBatch 后应能取到 tool_2")
        // 清理
        registry.unregister(name: "batch_tool_1")
        registry.unregister(name: "batch_tool_2")
    }

    /// registerBatch 空数组应为 no-op
    func testRegisterBatchEmptyArrayIsNoOp() {
        let countBefore = registry.toolCount
        registry.registerBatch(tools: [])
        XCTAssertEqual(registry.toolCount, countBefore, "空数组 registerBatch 应为 no-op")
    }

    /// registerBatch 同名工具应覆盖
    func testRegisterBatchOverridesSameName() async throws {
        let dummy = DummyTool(name: "calculate", result: "BATCH_OVERRIDE")
        registry.registerBatch(tools: [dummy])
        let tool = registry.getTool(named: "calculate")
        XCTAssertNotNil(tool, "registerBatch 覆盖后应能取到工具")
        let result = try await tool!.execute(arguments: [:])
        XCTAssertEqual(result, "BATCH_OVERRIDE", "registerBatch 同名应覆盖")
        // 恢复
        registry.register(tool: CalculatorTool())
    }

    /// registerBatch 后 toolCount 应增加对应数量
    func testRegisterBatchIncrementsToolCount() {
        let countBefore = registry.toolCount
        let dummy1 = DummyTool(name: "batch_count_1", result: "r1")
        let dummy2 = DummyTool(name: "batch_count_2", result: "r2")
        let dummy3 = DummyTool(name: "batch_count_3", result: "r3")
        registry.registerBatch(tools: [dummy1, dummy2, dummy3])
        XCTAssertEqual(registry.toolCount, countBefore + 3, "registerBatch 3 个工具后 toolCount 应增 3")
        // 清理
        registry.unregister(name: "batch_count_1")
        registry.unregister(name: "batch_count_2")
        registry.unregister(name: "batch_count_3")
    }

    /// getToolNames 应返回所有已注册工具名
    func testGetToolNamesReturnsAllRegisteredNames() {
        let names = registry.getToolNames()
        XCTAssertFalse(names.isEmpty, "getToolNames 不应为空")
        XCTAssertTrue(names.contains("calculate"), "getToolNames 应包含 calculate")
    }

    /// DateTimeTool 与 CalculatorTool 应遵循 Sendable 协议（新代码：@unchecked Sendable）
    func testDateTimeAndCalculatorConformToSendable() {
        // 编译期即可验证 Sendable 遵循，运行时仅做 sanity check
        let dateTime = DateTimeTool()
        let calculator = CalculatorTool()
        XCTAssertFalse(dateTime.definition.name.isEmpty, "DateTimeTool 应可实例化")
        XCTAssertFalse(calculator.definition.name.isEmpty, "CalculatorTool 应可实例化")
        XCTAssertEqual(dateTime.definition.name, "get_current_time")
        XCTAssertEqual(calculator.definition.name, "calculate")
    }

    // MARK: - @unchecked Sendable 并发执行测试

    /// DateTimeTool 和 CalculatorTool 标记为 @unchecked Sendable，
    /// 应可在 Task.detached（@Sendable 闭包）中安全捕获并正确执行。
    /// 若移除 @unchecked Sendable，此测试将无法编译。
    func testSendableToolsExecuteInDetachedTasks() async throws {
        let dateTime = DateTimeTool()
        let calculator = CalculatorTool()

        // Task.detached 的闭包必须为 @Sendable — @unchecked Sendable 允许捕获实例
        let dtTask = Task.detached { try await dateTime.execute(arguments: [:]) }
        let calcTask = Task.detached {
            try await calculator.execute(arguments: ["expression": "12 + 30"])
        }

        let dt = try await dtTask.value
        let calc = try await calcTask.value

        XCTAssertFalse(dt.isEmpty, "DateTimeTool 在 detached Task 中应返回非空结果")
        XCTAssertEqual(calc, "42", "CalculatorTool 在 detached Task 中应正确求值 12 + 30 = 42")
    }

    /// DateTimeTool 在多次并发 detached 调用中应保持稳定（验证 @unchecked Sendable 线程安全性）
    func testDateTimeToolSendableMultipleDetachedInvocations() async throws {
        let tool = DateTimeTool()

        let task1 = Task.detached { try await tool.execute(arguments: ["timezone": "Asia/Shanghai"]) }
        let task2 = Task.detached { try await tool.execute(arguments: ["timezone": "America/New_York"]) }
        let task3 = Task.detached { try await tool.execute(arguments: [:]) }

        let result1 = try await task1.value
        let result2 = try await task2.value
        let result3 = try await task3.value

        XCTAssertFalse(result1.isEmpty, "第一次并发调用应返回非空结果")
        XCTAssertFalse(result2.isEmpty, "第二次并发调用应返回非空结果")
        XCTAssertFalse(result3.isEmpty, "第三次并发调用应返回非空结果")
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
