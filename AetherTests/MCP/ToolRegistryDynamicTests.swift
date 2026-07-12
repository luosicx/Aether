import XCTest
@testable import Aether

/// Task 2 测试：MCP 工具自动注册到 ToolRegistry 的动态注册能力。
///
/// 覆盖范围：
/// 1. ToolRegistry 动态注册能力（unregister / registerBatch / getToolNames / toolCount）
/// 2. MCPToolAdapter 将 MCP 工具适配为 ToolProtocol（definition 映射 + execute 文本拼接）
/// 3. MCPClientManager 连接成功后自动注册工具、断开后自动注销
@MainActor
final class ToolRegistryDynamicTests: XCTestCase {
    private let registry = ToolRegistry.shared

    // MARK: - register 正常注册

    /// register 应成功注册工具，getTool 可取到
    func testRegisterAddsTool() {
        defer { registry.unregister(name: "dyn_register_test") }
        XCTAssertNil(registry.getTool(named: "dyn_register_test"), "注册前应不存在")
        registry.register(tool: DynTestTool(name: "dyn_register_test", result: "ok"))
        XCTAssertNotNil(registry.getTool(named: "dyn_register_test"), "注册后应可取到")
    }

    // MARK: - unregister 按名注销

    /// unregister 应移除已注册工具
    func testUnregisterRemovesTool() {
        registry.register(tool: DynTestTool(name: "dyn_unregister_test", result: "ok"))
        XCTAssertNotNil(registry.getTool(named: "dyn_unregister_test"))
        registry.unregister(name: "dyn_unregister_test")
        XCTAssertNil(registry.getTool(named: "dyn_unregister_test"), "注销后应取不到")
    }

    /// unregister 不存在的工具名不应报错，toolCount 不变
    func testUnregisterNonExistentDoesNotThrow() {
        let countBefore = registry.toolCount
        registry.unregister(name: "totally_nonexistent_tool_xyz_123")
        XCTAssertEqual(registry.toolCount, countBefore, "注销不存在的工具名不应改变 toolCount")
        XCTAssertNil(registry.getTool(named: "totally_nonexistent_tool_xyz_123"))
    }

    // MARK: - registerBatch 批量注册

    /// registerBatch 应一次性注册多个工具
    func testRegisterBatchAddsAllTools() {
        let countBefore = registry.toolCount
        let tools = [
            DynTestTool(name: "dyn_batch_1", result: "1"),
            DynTestTool(name: "dyn_batch_2", result: "2"),
            DynTestTool(name: "dyn_batch_3", result: "3")
        ]
        defer {
            tools.forEach { registry.unregister(name: $0.definition.name) }
        }
        registry.registerBatch(tools: tools)
        XCTAssertEqual(registry.toolCount, countBefore + 3, "批量注册 3 个工具后 toolCount 应 +3")
        XCTAssertNotNil(registry.getTool(named: "dyn_batch_1"))
        XCTAssertNotNil(registry.getTool(named: "dyn_batch_2"))
        XCTAssertNotNil(registry.getTool(named: "dyn_batch_3"))
    }

    // MARK: - 同名覆盖

    /// register 同名工具应覆盖旧工具，toolCount 不增加
    func testRegisterOverridesSameName() async throws {
        let countBefore = registry.toolCount
        defer { registry.unregister(name: "dyn_override_test") }
        registry.register(tool: DynTestTool(name: "dyn_override_test", result: "first"))
        let first = try await registry.getTool(named: "dyn_override_test")!.execute(arguments: [:])
        XCTAssertEqual(first, "first")
        // 同名覆盖
        registry.register(tool: DynTestTool(name: "dyn_override_test", result: "second"))
        XCTAssertEqual(registry.toolCount, countBefore + 1, "同名覆盖不应增加 toolCount")
        let second = try await registry.getTool(named: "dyn_override_test")!.execute(arguments: [:])
        XCTAssertEqual(second, "second", "同名注册应返回新工具结果")
    }

    // MARK: - getToolNames

    /// getToolNames 应返回所有已注册工具名（包含新注册的工具）
    func testGetToolNamesContainsRegistered() {
        defer { registry.unregister(name: "dyn_names_test") }
        registry.register(tool: DynTestTool(name: "dyn_names_test", result: "ok"))
        let names = registry.getToolNames()
        XCTAssertTrue(names.contains("dyn_names_test"), "getToolNames 应包含新注册的工具名")
        XCTAssertEqual(names.count, registry.toolCount, "getToolNames 数量应与 toolCount 一致")
    }

    // MARK: - toolCount 正确

    /// toolCount 应随注册/注销正确增减
    func testToolCountReflectsChanges() {
        let base = registry.toolCount
        defer { registry.unregister(name: "dyn_count_a"); registry.unregister(name: "dyn_count_b") }
        registry.register(tool: DynTestTool(name: "dyn_count_a", result: "a"))
        XCTAssertEqual(registry.toolCount, base + 1)
        registry.register(tool: DynTestTool(name: "dyn_count_b", result: "b"))
        XCTAssertEqual(registry.toolCount, base + 2)
        registry.unregister(name: "dyn_count_a")
        XCTAssertEqual(registry.toolCount, base + 1, "注销后 toolCount 应减少")
    }

    // MARK: - MCPToolAdapter

    /// MCPToolAdapter 应正确映射 definition（name/description/parameters）
    func testMCPToolAdapterDefinitionMapping() {
        let client = StubToolCallClient(contents: [])
        let tool = MCPTool(name: "mcp_tool_def", description: "MCP 测试工具", inputSchema: ["type": "object"])
        let adapter = MCPToolAdapter(tool: tool, client: client)
        XCTAssertEqual(adapter.definition.name, "mcp_tool_def")
        XCTAssertEqual(adapter.definition.description, "MCP 测试工具")
        XCTAssertEqual(adapter.definition.parameters["type"] as? String, "object")
    }

    /// MCPToolAdapter.execute 应拼接所有 text 内容块（多块用换行连接）
    func testMCPToolAdapterExecuteJoinsTextContent() async throws {
        let client = StubToolCallClient(contents: [
            MCPToolCallResult.Content(type: "text", text: "line1", data: nil, mimeType: nil),
            MCPToolCallResult.Content(type: "text", text: "line2", data: nil, mimeType: nil)
        ])
        let tool = MCPTool(name: "mcp_tool_exec", description: "执行", inputSchema: [:])
        let adapter = MCPToolAdapter(tool: tool, client: client)
        let result = try await adapter.execute(arguments: ["q": "hello"])
        XCTAssertEqual(result, "line1\nline2", "应拼接多个 text 内容块")
    }

    /// MCPToolAdapter.execute 仅有单个 text 块时返回该文本
    func testMCPToolAdapterExecuteSingleText() async throws {
        let client = StubToolCallClient(contents: [
            MCPToolCallResult.Content(type: "text", text: "only", data: nil, mimeType: nil)
        ])
        let adapter = MCPToolAdapter(tool: MCPTool(name: "t", description: "d", inputSchema: [:]), client: client)
        let executeResult = try await adapter.execute(arguments: [:])
        XCTAssertEqual(executeResult, "only")
    }

    // MARK: - MCPClientManager 自动注册/注销集成

    /// 连接成功后应自动将 MCP 工具注册到 ToolRegistry；断开后自动注销
    func testManagerAutoRegistersAndUnregistersTools() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "mcp_autoreg_a", description: "A", inputSchema: ["type": "object"]),
                MCPTool(name: "mcp_autoreg_b", description: "B", inputSchema: ["type": "object"])
            ])
        })
        let config = MCPConfig(id: "autoreg-server", name: "AutoReg",
                               transport: .sse(url: "http://localhost/sse", headers: nil), enabled: true)

        XCTAssertNil(registry.getTool(named: "mcp_autoreg_a"), "连接前工具不应注册")
        XCTAssertNil(registry.getTool(named: "mcp_autoreg_b"))

        try await manager.connect(config: config)

        XCTAssertNotNil(registry.getTool(named: "mcp_autoreg_a"), "连接后应自动注册工具 A")
        XCTAssertNotNil(registry.getTool(named: "mcp_autoreg_b"), "连接后应自动注册工具 B")
        XCTAssertTrue(registry.getToolNames().contains("mcp_autoreg_a"))

        await manager.disconnect(serverID: "autoreg-server")

        XCTAssertNil(registry.getTool(named: "mcp_autoreg_a"), "断开后应自动注销工具 A")
        XCTAssertNil(registry.getTool(named: "mcp_autoreg_b"), "断开后应自动注销工具 B")
    }

    /// disconnectAll 应注销所有 Server 注册的工具
    func testManagerDisconnectAllUnregistersAllTools() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "mcp_all_\(config.id)", description: "T", inputSchema: [:])
            ])
        })
        try await manager.connect(config: MCPConfig(id: "all-srv-1", name: "S1",
            transport: .sse(url: "http://1", headers: nil), enabled: true))
        try await manager.connect(config: MCPConfig(id: "all-srv-2", name: "S2",
            transport: .sse(url: "http://2", headers: nil), enabled: true))
        XCTAssertNotNil(registry.getTool(named: "mcp_all_all-srv-1"))
        XCTAssertNotNil(registry.getTool(named: "mcp_all_all-srv-2"))

        await manager.disconnectAll()

        XCTAssertNil(registry.getTool(named: "mcp_all_all-srv-1"), "disconnectAll 后应全部注销")
        XCTAssertNil(registry.getTool(named: "mcp_all_all-srv-2"))
    }
}

// MARK: - 测试用占位工具

/// 可配置 name 与返回值的测试工具，execute 返回固定字符串
private final class DynTestTool: ToolProtocol {
    private let name: String
    private let result: String

    init(name: String, result: String) {
        self.name = name
        self.result = result
    }

    var definition: ToolDefinition {
        ToolDefinition(name: name, description: "动态测试工具", parameters: ["type": "object"])
    }

    func execute(arguments: [String: Any]) async throws -> String {
        result
    }
}

// MARK: - 测试用 MCP 客户端桩（可控 callTool 返回内容）

/// 仅用于 MCPToolAdapter 单元测试的可控 MCPClientProtocol 桩，
/// callTool 返回构造时传入的固定内容块。
private actor StubToolCallClient: MCPClientProtocol {
    let config: MCPConfig
    private let contents: [MCPToolCallResult.Content]

    init(contents: [MCPToolCallResult.Content]) {
        self.config = MCPConfig(id: "stub", name: "stub",
                                transport: .sse(url: "http://stub", headers: nil), enabled: true)
        self.contents = contents
    }

    func connect() async throws {}
    func disconnect() async {}
    func listTools() async throws -> [MCPTool] { [] }
    func listResources() async throws -> [MCPResource] { [] }
    func listPrompts() async throws -> [MCPPrompt] { [] }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
        MCPToolCallResult(content: contents, isError: false)
    }

    func readResource(uri: String) async throws -> [MCPResourceContent] { [] }
    func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult {
        MCPPromptResult(description: nil, messages: [])
    }
}
