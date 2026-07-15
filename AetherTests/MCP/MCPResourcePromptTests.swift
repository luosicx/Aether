import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// MCP 资源与提示词模板服务单元测试。
///
/// 覆盖范围：
/// 1. MCPResourceService 初始化与获取资源列表
/// 2. MCPPromptService 初始化与获取提示词列表
/// 3. readResource 与 getPrompt 调用（使用 MockMCPClient 注入）
/// 4. 多 Server 资源/提示词聚合
///
/// 复用 MCPClientTests 中定义的 MockMCPClient（同测试 target，internal 可见）。
final class MCPResourcePromptTests: XCTestCase {

    // MARK: - 1. MCPResourceService 初始化与获取资源列表

    /// 无连接 Server 时资源列表应为空
    @MainActor
    func testResourceServiceInitWithNoServers() async {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPResourceService(clientManager: manager)

        let resources = await service.getAllResources()
        XCTAssertTrue(resources.isEmpty, "无连接 Server 时资源列表应为空")
    }

    /// 单 Server 连接后应返回其资源列表
    @MainActor
    func testResourceServiceGetAllResources() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, resources: [
                MCPResource(uri: "file:///test1.txt", name: "测试1", description: "描述1", mimeType: "text/plain"),
                MCPResource(uri: "file:///test2.txt", name: "测试2", description: nil, mimeType: nil)
            ])
        })
        try await manager.connect(config: makeTestConfig(id: "res-server-1", name: "资源 Server 1"))

        let service = MCPResourceService(clientManager: manager)
        let resources = await service.getAllResources()

        XCTAssertEqual(resources.count, 2, "应有 2 个资源")
        XCTAssertEqual(resources[0].serverID, "res-server-1", "serverID 应一致")
        XCTAssertEqual(resources[0].resource.uri, "file:///test1.txt", "uri 应一致")
        XCTAssertEqual(resources[0].resource.name, "测试1", "name 应一致")
        XCTAssertEqual(resources[0].resource.description, "描述1", "description 应一致")
        XCTAssertEqual(resources[0].resource.mimeType, "text/plain", "mimeType 应一致")
        XCTAssertEqual(resources[1].resource.uri, "file:///test2.txt", "第二个 uri 应一致")
        XCTAssertNil(resources[1].resource.description, "第二个 description 应为 nil")
    }

    /// 多 Server 资源应正确聚合
    @MainActor
    func testResourceServiceAggregatesMultipleServers() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, resources: [
                MCPResource(uri: "file:///\(config.id).txt", name: config.name, description: nil, mimeType: "text/plain")
            ])
        })
        try await manager.connect(config: makeTestConfig(id: "multi-1", name: "Multi 1"))
        try await manager.connect(config: makeTestConfig(id: "multi-2", name: "Multi 2"))

        let service = MCPResourceService(clientManager: manager)
        let resources = await service.getAllResources()

        XCTAssertEqual(resources.count, 2, "应聚合 2 个 Server 的资源")
        let serverIDs = Set(resources.map(\.serverID))
        XCTAssertTrue(serverIDs.contains("multi-1"), "应包含 multi-1")
        XCTAssertTrue(serverIDs.contains("multi-2"), "应包含 multi-2")
    }

    // MARK: - 2. readResource 调用测试

    /// readResource 应返回指定资源内容
    @MainActor
    func testResourceServiceReadResource() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, resources: [
                MCPResource(uri: "file:///test.txt", name: "测试", description: nil, mimeType: "text/plain")
            ])
        })
        try await manager.connect(config: makeTestConfig(id: "read-server", name: "读取 Server"))

        let service = MCPResourceService(clientManager: manager)
        let content = try await service.readResource(serverID: "read-server", uri: "file:///test.txt")

        XCTAssertEqual(content, "mock content", "读取的资源内容应一致（MockMCPClient 返回固定文本）")
    }

    /// 不存在的 Server 读取资源应抛出 notConnected
    @MainActor
    func testResourceServiceReadResourceFailsForUnknownServer() async {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPResourceService(clientManager: manager)

        do {
            _ = try await service.readResource(serverID: "non-existent", uri: "file:///x.txt")
            XCTFail("应抛出 notConnected 错误")
        } catch let error as MCPError {
            if case .notConnected = error {
                // 预期行为
            } else {
                XCTFail("应为 notConnected 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }
    }

    // MARK: - 3. MCPPromptService 初始化与获取提示词列表

    /// 无连接 Server 时提示词列表应为空
    @MainActor
    func testPromptServiceInitWithNoServers() async {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPPromptService(clientManager: manager)

        let prompts = await service.getAllPrompts()
        XCTAssertTrue(prompts.isEmpty, "无连接 Server 时提示词列表应为空")
    }

    /// 单 Server 连接后应返回其提示词列表
    @MainActor
    func testPromptServiceGetAllPrompts() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, prompts: [
                MCPPrompt(name: "greeting", description: "问候提示", arguments: [
                    MCPPromptArgument(name: "name", description: "称呼", required: true)
                ]),
                MCPPrompt(name: "summary", description: "摘要提示", arguments: nil)
            ])
        })
        try await manager.connect(config: makeTestConfig(id: "prompt-server-1", name: "提示 Server 1"))

        let service = MCPPromptService(clientManager: manager)
        let prompts = await service.getAllPrompts()

        XCTAssertEqual(prompts.count, 2, "应有 2 个提示模板")
        XCTAssertEqual(prompts[0].serverID, "prompt-server-1", "serverID 应一致")
        XCTAssertEqual(prompts[0].prompt.name, "greeting", "name 应一致")
        XCTAssertEqual(prompts[0].prompt.description, "问候提示", "description 应一致")
        XCTAssertEqual(prompts[0].prompt.arguments?.count, 1, "greeting 应有 1 个参数")
        XCTAssertEqual(prompts[0].prompt.arguments?[0].name, "name", "参数名应为 name")
        XCTAssertTrue(prompts[0].prompt.arguments?[0].required ?? false, "参数应必填")
        XCTAssertEqual(prompts[1].prompt.name, "summary", "第二个 name 应一致")
        XCTAssertNil(prompts[1].prompt.arguments, "summary 无参数")
    }

    /// 多 Server 提示词应正确聚合
    @MainActor
    func testPromptServiceAggregatesMultipleServers() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, prompts: [
                MCPPrompt(name: "prompt_\(config.id)", description: config.name, arguments: nil)
            ])
        })
        try await manager.connect(config: makeTestConfig(id: "p-multi-1", name: "P Multi 1"))
        try await manager.connect(config: makeTestConfig(id: "p-multi-2", name: "P Multi 2"))

        let service = MCPPromptService(clientManager: manager)
        let prompts = await service.getAllPrompts()

        XCTAssertEqual(prompts.count, 2, "应聚合 2 个 Server 的提示模板")
        let promptNames = Set(prompts.map(\.prompt.name))
        XCTAssertTrue(promptNames.contains("prompt_p-multi-1"), "应包含 prompt_p-multi-1")
        XCTAssertTrue(promptNames.contains("prompt_p-multi-2"), "应包含 prompt_p-multi-2")
    }

    // MARK: - 4. getPrompt 调用测试

    /// getPrompt 应返回指定提示模板内容
    @MainActor
    func testPromptServiceGetPrompt() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, prompts: [
                MCPPrompt(name: "greeting", description: "问候", arguments: nil)
            ])
        })
        try await manager.connect(config: makeTestConfig(id: "get-prompt-server", name: "获取提示 Server"))

        let service = MCPPromptService(clientManager: manager)
        let content = try await service.getPrompt(
            serverID: "get-prompt-server",
            name: "greeting",
            arguments: ["name": "Alice"]
        )

        XCTAssertEqual(content, "mock message", "获取的提示内容应一致（MockMCPClient 返回固定文本）")
    }

    /// 不存在的 Server 获取提示应抛出 notConnected
    @MainActor
    func testPromptServiceGetPromptFailsForUnknownServer() async {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPPromptService(clientManager: manager)

        do {
            _ = try await service.getPrompt(serverID: "non-existent", name: "greeting", arguments: [:])
            XCTFail("应抛出 notConnected 错误")
        } catch let error as MCPError {
            if case .notConnected = error {
                // 预期行为
            } else {
                XCTFail("应为 notConnected 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }
    }

    /// getPrompt 传空参数应正常返回
    @MainActor
    func testPromptServiceGetPromptWithEmptyArguments() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, prompts: [
                MCPPrompt(name: "simple", description: "无参数提示", arguments: nil)
            ])
        })
        try await manager.connect(config: makeTestConfig(id: "empty-arg-server", name: "空参数 Server"))

        let service = MCPPromptService(clientManager: manager)
        let content = try await service.getPrompt(
            serverID: "empty-arg-server",
            name: "simple",
            arguments: [:]
        )

        XCTAssertEqual(content, "mock message", "空参数也应正常返回内容")
    }

    // MARK: - 辅助方法

    /// 创建测试用 MCPConfig
    private func makeTestConfig(id: String, name: String = "测试 Server") -> MCPConfig {
        MCPConfig(
            id: id,
            name: name,
            transport: .sse(url: "http://localhost:9999/sse", headers: nil),
            enabled: true
        )
    }
}
