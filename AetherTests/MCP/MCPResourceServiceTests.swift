import XCTest
import AetherFoundation
@testable import Aether

/// Task 18 阶段 5: MCPResourceService 单元测试。
///
/// 覆盖：
/// - getAllResources 聚合多个 Server 的资源列表
/// - getAllResources 单个 Server 拉取失败不中断整体
/// - getAllResources 无已连接 Server 时返回空
/// - readResource 成功路径：拼接 text 块
/// - readResource 未连接 Server 抛 MCPError.notConnected
/// - readResource 透传底层错误
@MainActor
final class MCPResourceServiceTests: XCTestCase {

    // MARK: - getAllResources

    /// 空管理器应返回空列表
    func testGetAllResourcesEmptyManager() async {
        let manager = MCPClientManager()
        let service = MCPResourceService(clientManager: manager)
        let resources = await service.getAllResources()
        XCTAssertTrue(resources.isEmpty, "无 Server 时应返回空列表")
    }

    /// 多 Server 资源聚合应包含所有 Server 的资源
    func testGetAllResourcesAggregatesMultipleServers() async throws {
        let resource1 = MCPResource(uri: "file:///a", name: "A")
        let resource2 = MCPResource(uri: "file:///b", name: "B")
        let resource3 = MCPResource(uri: "file:///c", name: "C")

        let client1 = StubMCPClient()
        client1.resources = [resource1, resource2]
        let client2 = StubMCPClient()
        client2.resources = [resource3]

        let manager = MCPClientManager(clientFactory: { config in
            config.id == "s1" ? client1 : client2
        })

        let config1 = MCPConfig(id: "s1", name: "Server1", transport: .sse(url: "http://s1", headers: nil), enabled: true)
        let config2 = MCPConfig(id: "s2", name: "Server2", transport: .sse(url: "http://s2", headers: nil), enabled: true)

        try await manager.connect(config: config1)
        try await manager.connect(config: config2)

        let service = MCPResourceService(clientManager: manager)
        let resources = await service.getAllResources()
        XCTAssertEqual(resources.count, 3, "应聚合 3 个资源")
        let uris = Set(resources.map { $0.resource.uri })
        XCTAssertEqual(uris, ["file:///a", "file:///b", "file:///c"])
    }

    /// 单个 Server 拉取失败时应跳过，不影响其他 Server
    func testGetAllResourcesSkipsFailingServer() async throws {
        let goodClient = StubMCPClient()
        goodClient.resources = [MCPResource(uri: "file:///good", name: "Good")]
        let failingClient = StubMCPClient()
        failingClient.listResourcesError = MCPError.connectionFailed("故意失败")

        let manager = MCPClientManager(clientFactory: { config in
            config.id == "good" ? goodClient : failingClient
        })

        try await manager.connect(config: MCPConfig(id: "good", name: "Good", transport: .sse(url: "http://good", headers: nil), enabled: true))
        try await manager.connect(config: MCPConfig(id: "bad", name: "Bad", transport: .sse(url: "http://bad", headers: nil), enabled: true))

        let service = MCPResourceService(clientManager: manager)
        let resources = await service.getAllResources()
        XCTAssertEqual(resources.count, 1, "失败的 Server 应被跳过，只返回 1 个资源")
        XCTAssertEqual(resources.first?.resource.uri, "file:///good")
    }

    // MARK: - readResource

    /// 成功读取应拼接 text 块
    func testReadResourceSuccess() async throws {
        let client = StubMCPClient()
        client.resourceContents = [
            MCPResourceContent(uri: "file:///x", text: "line1"),
            MCPResourceContent(uri: "file:///x", text: "line2")
        ]
        let manager = MCPClientManager(clientFactory: { _ in client })
        try await manager.connect(config: MCPConfig(id: "s1", name: "S1", transport: .sse(url: "http://s1", headers: nil), enabled: true))

        let service = MCPResourceService(clientManager: manager)
        let content = try await service.readResource(serverID: "s1", uri: "file:///x")
        XCTAssertEqual(content, "line1\nline2")
    }

    /// 无 text 块应返回空字符串
    func testReadResourceNoTextReturnsEmpty() async throws {
        let client = StubMCPClient()
        client.resourceContents = [
            MCPResourceContent(uri: "file:///x", text: nil, blob: "binary")
        ]
        let manager = MCPClientManager(clientFactory: { _ in client })
        try await manager.connect(config: MCPConfig(id: "s1", name: "S1", transport: .sse(url: "http://s1", headers: nil), enabled: true))

        let service = MCPResourceService(clientManager: manager)
        let content = try await service.readResource(serverID: "s1", uri: "file:///x")
        XCTAssertEqual(content, "")
    }

    /// 未连接 Server 应抛 MCPError.notConnected
    func testReadResourceNotConnectedThrows() async {
        let manager = MCPClientManager()
        let service = MCPResourceService(clientManager: manager)
        do {
            _ = try await service.readResource(serverID: "nonexistent", uri: "file:///x")
            XCTFail("未连接的 Server 应抛错")
        } catch {
            // 预期抛错
        }
    }

    /// 底层 readResource 错误应透传
    func testReadResourcePropagatesError() async throws {
        let client = StubMCPClient()
        client.readResourceError = MCPError.invalidResponse("解析失败")
        let manager = MCPClientManager(clientFactory: { _ in client })
        try await manager.connect(config: MCPConfig(id: "s1", name: "S1", transport: .sse(url: "http://s1", headers: nil), enabled: true))

        let service = MCPResourceService(clientManager: manager)
        do {
            _ = try await service.readResource(serverID: "s1", uri: "file:///x")
            XCTFail("应透传错误")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - 测试桩

    private final class StubMCPClient: MCPClientProtocol {
        var config: MCPConfig {
            MCPConfig(id: "stub", name: "Stub", transport: .sse(url: "http://stub", headers: nil), enabled: true)
        }
        var resources: [MCPResource] = []
        var resourceContents: [MCPResourceContent] = []
        var listResourcesError: Error?
        var readResourceError: Error?

        func connect() async throws {}
        func disconnect() async {}
        func listTools() async throws -> [MCPTool] { [] }
        func listResources() async throws -> [MCPResource] {
            if let error = listResourcesError { throw error }
            return resources
        }
        func listPrompts() async throws -> [MCPPrompt] { [] }
        func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
            MCPToolCallResult(content: [])
        }
        func readResource(uri: String) async throws -> [MCPResourceContent] {
            if let error = readResourceError { throw error }
            return resourceContents
        }
        func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult {
            MCPPromptResult(messages: [])
        }
    }
}
