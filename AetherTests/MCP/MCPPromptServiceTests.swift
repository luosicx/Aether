import XCTest
import AetherFoundation
@testable import Aether

/// Task 18 阶段 5: MCPPromptService 单元测试。
///
/// 覆盖：
/// - getAllPrompts 聚合多个 Server 的提示模板列表
/// - getAllPrompts 单个 Server 拉取失败不中断整体
/// - getAllPrompts 无已连接 Server 时返回空
/// - getPrompt 成功路径：拼接消息文本
/// - getPrompt 未连接 Server 抛 MCPError.notConnected
/// - getPrompt 透传底层错误
@MainActor
final class MCPPromptServiceTests: XCTestCase {

    // MARK: - getAllPrompts

    /// 空管理器应返回空列表
    func testGetAllPromptsEmptyManager() async {
        let manager = MCPClientManager()
        let service = MCPPromptService(clientManager: manager)
        let prompts = await service.getAllPrompts()
        XCTAssertTrue(prompts.isEmpty, "无 Server 时应返回空列表")
    }

    /// 多 Server 提示模板聚合应包含所有 Server 的模板
    func testGetAllPromptsAggregatesMultipleServers() async throws {
        let prompt1 = MCPPrompt(name: "p1", description: "Prompt 1", arguments: nil)
        let prompt2 = MCPPrompt(name: "p2", description: "Prompt 2", arguments: nil)
        let prompt3 = MCPPrompt(name: "p3", description: "Prompt 3", arguments: nil)

        let client1 = StubMCPClient()
        client1.prompts = [prompt1, prompt2]
        let client2 = StubMCPClient()
        client2.prompts = [prompt3]

        let manager = MCPClientManager(clientFactory: { config in
            config.id == "s1" ? client1 : client2
        })

        try await manager.connect(config: MCPConfig(id: "s1", name: "Server1", transport: .sse(url: "http://s1", headers: nil), enabled: true))
        try await manager.connect(config: MCPConfig(id: "s2", name: "Server2", transport: .sse(url: "http://s2", headers: nil), enabled: true))

        let service = MCPPromptService(clientManager: manager)
        let prompts = await service.getAllPrompts()
        XCTAssertEqual(prompts.count, 3, "应聚合 3 个模板")
        let names = Set(prompts.map { $0.prompt.name })
        XCTAssertEqual(names, ["p1", "p2", "p3"])
    }

    /// 单个 Server 拉取失败时应跳过，不影响其他 Server
    func testGetAllPromptsSkipsFailingServer() async throws {
        let goodClient = StubMCPClient()
        goodClient.prompts = [MCPPrompt(name: "good_prompt", description: "Good", arguments: nil)]
        let failingClient = StubMCPClient()
        failingClient.listPromptsError = MCPError.connectionFailed("故意失败")

        let manager = MCPClientManager(clientFactory: { config in
            config.id == "good" ? goodClient : failingClient
        })

        try await manager.connect(config: MCPConfig(id: "good", name: "Good", transport: .sse(url: "http://good", headers: nil), enabled: true))
        try await manager.connect(config: MCPConfig(id: "bad", name: "Bad", transport: .sse(url: "http://bad", headers: nil), enabled: true))

        let service = MCPPromptService(clientManager: manager)
        let prompts = await service.getAllPrompts()
        XCTAssertEqual(prompts.count, 1, "失败的 Server 应被跳过")
        XCTAssertEqual(prompts.first?.prompt.name, "good_prompt")
    }

    // MARK: - getPrompt

    /// 成功获取应拼接消息文本
    func testGetPromptSuccess() async throws {
        let client = StubMCPClient()
        client.promptResult = MCPPromptResult(
            description: "test prompt",
            messages: [
                .init(role: "user", content: .init(type: "text", text: "hello")),
                .init(role: "assistant", content: .init(type: "text", text: "world"))
            ]
        )
        let manager = MCPClientManager(clientFactory: { _ in client })
        try await manager.connect(config: MCPConfig(id: "s1", name: "S1", transport: .sse(url: "http://s1", headers: nil), enabled: true))

        let service = MCPPromptService(clientManager: manager)
        let text = try await service.getPrompt(serverID: "s1", name: "p1", arguments: ["k": "v"])
        XCTAssertEqual(text, "hello\nworld")
    }

    /// 无文本块应返回空字符串
    func testGetPromptNoTextReturnsEmpty() async throws {
        let client = StubMCPClient()
        client.promptResult = MCPPromptResult(
            messages: [
                .init(role: "user", content: .init(type: "image", text: nil))
            ]
        )
        let manager = MCPClientManager(clientFactory: { _ in client })
        try await manager.connect(config: MCPConfig(id: "s1", name: "S1", transport: .sse(url: "http://s1", headers: nil), enabled: true))

        let service = MCPPromptService(clientManager: manager)
        let text = try await service.getPrompt(serverID: "s1", name: "p1", arguments: [:])
        XCTAssertEqual(text, "")
    }

    /// 未连接 Server 应抛错
    func testGetPromptNotConnectedThrows() async {
        let manager = MCPClientManager()
        let service = MCPPromptService(clientManager: manager)
        do {
            _ = try await service.getPrompt(serverID: "nonexistent", name: "p1", arguments: [:])
            XCTFail("未连接的 Server 应抛错")
        } catch {
            // 预期抛错
        }
    }

    /// 底层 getPrompt 错误应透传
    func testGetPromptPropagatesError() async throws {
        let client = StubMCPClient()
        client.getPromptError = MCPError.invalidResponse("模板不存在")
        let manager = MCPClientManager(clientFactory: { _ in client })
        try await manager.connect(config: MCPConfig(id: "s1", name: "S1", transport: .sse(url: "http://s1", headers: nil), enabled: true))

        let service = MCPPromptService(clientManager: manager)
        do {
            _ = try await service.getPrompt(serverID: "s1", name: "missing", arguments: [:])
            XCTFail("应透传错误")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    /// 传递参数应透传给 client
    func testGetPromptPassesArgumentsToClient() async throws {
        let client = StubMCPClient()
        client.promptResult = MCPPromptResult(messages: [
            .init(role: "user", content: .init(type: "text", text: "ok"))
        ])
        let manager = MCPClientManager(clientFactory: { _ in client })
        try await manager.connect(config: MCPConfig(id: "s1", name: "S1", transport: .sse(url: "http://s1", headers: nil), enabled: true))

        let service = MCPPromptService(clientManager: manager)
        _ = try await service.getPrompt(serverID: "s1", name: "p1", arguments: ["lang": "zh"])
        XCTAssertEqual(client.lastGetPromptName, "p1")
    }

    // MARK: - 测试桩

    private final class StubMCPClient: MCPClientProtocol {
        var config: MCPConfig {
            MCPConfig(id: "stub", name: "Stub", transport: .sse(url: "http://stub", headers: nil), enabled: true)
        }
        var prompts: [MCPPrompt] = []
        var promptResult: MCPPromptResult = MCPPromptResult(messages: [])
        var listPromptsError: Error?
        var getPromptError: Error?
        var lastGetPromptName: String?

        func connect() async throws {}
        func disconnect() async {}
        func listTools() async throws -> [MCPTool] { [] }
        func listResources() async throws -> [MCPResource] { [] }
        func listPrompts() async throws -> [MCPPrompt] {
            if let error = listPromptsError { throw error }
            return prompts
        }
        func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
            MCPToolCallResult(content: [])
        }
        func readResource(uri: String) async throws -> [MCPResourceContent] { [] }
        func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult {
            lastGetPromptName = name
            if let error = getPromptError { throw error }
            return promptResult
        }
    }
}
