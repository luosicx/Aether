import XCTest
import AetherFoundation
@testable import Aether

/// Task 18 阶段 5: MCPToolAdapter 单元测试。
///
/// 覆盖：
/// - 构造：definition.name 加 Server 前缀，description/inputSchema 透传
/// - execute 成功路径：委托 mcpClient.callTool 返回的 text 块以 \n 连接
/// - execute 多 text 块拼接
/// - execute 无 text 块返回空字符串
/// - execute 失败路径：透传错误并记录审计
/// - originalName / registeredName 计算属性
@MainActor
final class MCPToolAdapterTests: XCTestCase {

    // MARK: - 构造与元信息

    /// definition.name 应为 serverID__toolName 格式
    func testDefinitionNameHasServerPrefix() {
        let tool = MCPTool(name: "search", description: "搜索", inputSchema: ["type": "object"])
        let adapter = MCPToolAdapter(tool: tool, client: StubMCPClient(), serverID: "myServer")
        XCTAssertTrue(adapter.definition.name.contains("__"), "工具名应包含 __ 分隔符")
        XCTAssertTrue(adapter.definition.name.hasPrefix("myServer"), "工具名应以 serverID 开头")
        XCTAssertTrue(adapter.definition.name.contains("search"), "工具名应包含原名")
    }

    /// description 与 inputSchema 应透传
    func testDefinitionPassesThroughMetadata() {
        let tool = MCPTool(name: "calc", description: "计算器", inputSchema: ["type": "object", "properties": [:]])
        let adapter = MCPToolAdapter(tool: tool, client: StubMCPClient(), serverID: "srv1")
        XCTAssertEqual(adapter.definition.description, "计算器")
        XCTAssertNotNil(adapter.definition.parameters)
    }

    /// originalName 应为原始工具名（无前缀）
    func testOriginalName() {
        let tool = MCPTool(name: "get_weather", description: "", inputSchema: [:])
        let adapter = MCPToolAdapter(tool: tool, client: StubMCPClient(), serverID: "srv")
        XCTAssertEqual(adapter.originalName, "get_weather")
    }

    /// registeredName 应等于 definition.name
    func testRegisteredNameMatchesDefinition() {
        let tool = MCPTool(name: "fetch", description: "", inputSchema: [:])
        let adapter = MCPToolAdapter(tool: tool, client: StubMCPClient(), serverID: "srv2")
        XCTAssertEqual(adapter.registeredName, adapter.definition.name)
    }

    // MARK: - execute 成功路径

    /// 单个 text 块应原样返回
    func testExecuteSingleTextBlock() async throws {
        let client = StubMCPClient()
        client.callToolResult = MCPToolCallResult(content: [
            .init(type: "text", text: "hello world")
        ])
        let adapter = MCPToolAdapter(
            tool: MCPTool(name: "tool1", description: "", inputSchema: [:]),
            client: client,
            serverID: "srv"
        )
        let result = try await adapter.execute(arguments: ["key": "value"])
        XCTAssertEqual(result, "hello world")
    }

    /// 多个 text 块应以换行连接
    func testExecuteMultipleTextBlocksJoinedByNewline() async throws {
        let client = StubMCPClient()
        client.callToolResult = MCPToolCallResult(content: [
            .init(type: "text", text: "line1"),
            .init(type: "text", text: "line2"),
            .init(type: "text", text: "line3")
        ])
        let adapter = MCPToolAdapter(
            tool: MCPTool(name: "tool2", description: "", inputSchema: [:]),
            client: client,
            serverID: "srv"
        )
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "line1\nline2\nline3")
    }

    /// 无 text 块应返回空字符串
    func testExecuteNoTextBlocksReturnsEmpty() async throws {
        let client = StubMCPClient()
        client.callToolResult = MCPToolCallResult(content: [
            .init(type: "image", data: "base64data", mimeType: "image/png")
        ])
        let adapter = MCPToolAdapter(
            tool: MCPTool(name: "tool3", description: "", inputSchema: [:]),
            client: client,
            serverID: "srv"
        )
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "", "无 text 块应返回空字符串")
    }

    /// 空 content 应返回空字符串
    func testExecuteEmptyContentReturnsEmpty() async throws {
        let client = StubMCPClient()
        client.callToolResult = MCPToolCallResult(content: [])
        let adapter = MCPToolAdapter(
            tool: MCPTool(name: "tool4", description: "", inputSchema: [:]),
            client: client,
            serverID: "srv"
        )
        let result = try await adapter.execute(arguments: [:])
        XCTAssertEqual(result, "")
    }

    // MARK: - execute 失败路径

    /// callTool 抛错应透传
    func testExecutePropagatesError() async throws {
        let client = StubMCPClient()
        client.callToolError = MCPError.connectionFailed("模拟连接失败")
        let adapter = MCPToolAdapter(
            tool: MCPTool(name: "failing", description: "", inputSchema: [:]),
            client: client,
            serverID: "srv"
        )
        do {
            _ = try await adapter.execute(arguments: [:])
            XCTFail("应抛出错误")
        } catch {
            // 预期抛错
            XCTAssertNotNil(error)
        }
    }

    // MARK: - 参数透传

    /// execute 应将原 toolName（不含前缀）传给 mcpClient.callTool
    func testExecutePassesOriginalNameToClient() async throws {
        let client = StubMCPClient()
        client.callToolResult = MCPToolCallResult(content: [.init(type: "text", text: "ok")])
        let adapter = MCPToolAdapter(
            tool: MCPTool(name: "original_name", description: "", inputSchema: [:]),
            client: client,
            serverID: "srv"
        )
        _ = try await adapter.execute(arguments: ["k": "v"])
        XCTAssertEqual(client.lastCallToolName, "original_name", "应使用原名调用 client")
    }

    // MARK: - 测试桩

    /// 可配置的 MCPClient 桩
    private final class StubMCPClient: MCPClientProtocol {
        var config: MCPConfig {
            MCPConfig(id: "stub", name: "Stub", transport: .sse(url: "http://stub", headers: nil), enabled: true)
        }
        var callToolResult: MCPToolCallResult = MCPToolCallResult(content: [])
        var callToolError: Error?
        var lastCallToolName: String?

        func connect() async throws {}
        func disconnect() async {}
        func listTools() async throws -> [MCPTool] { [] }
        func listResources() async throws -> [MCPResource] { [] }
        func listPrompts() async throws -> [MCPPrompt] { [] }
        func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
            lastCallToolName = name
            if let error = callToolError { throw error }
            return callToolResult
        }
        func readResource(uri: String) async throws -> [MCPResourceContent] { [] }
        func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult {
            MCPPromptResult(messages: [])
        }
    }
}
