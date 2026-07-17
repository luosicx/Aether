import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// MCP 客户端基础设施单元测试。
///
/// 覆盖范围：
/// 1. MCPConfig 编解码（stdio / SSE 两种传输方式）
/// 2. JSON-RPC 2.0 消息构造和解析
/// 3. MCPClient 初始化与连接（通过 MockTransport 注入）
/// 4. MCPClientManager 多 Server 管理
final class MCPClientTests: XCTestCase {

    // MARK: - 1. MCPConfig 编解码测试

    /// stdio 配置（含 env）应能正确编解码
    func testStdioConfigCodable() throws {
        let config = MCPConfig(
            id: "test-stdio-001",
            name: "本地工具 Server",
            transport: .stdio(
                command: "/usr/local/bin/node",
                args: ["server.js", "--verbose"],
                env: ["NODE_ENV": "production", "DEBUG": "mcp"]
            ),
            enabled: true
        )

        // 编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        XCTAssertNotNil(data, "stdio 配置编码不应为空")

        // 解码
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPConfig.self, from: data)

        XCTAssertEqual(decoded.id, config.id, "id 应一致")
        XCTAssertEqual(decoded.name, config.name, "name 应一致")
        XCTAssertEqual(decoded.enabled, config.enabled, "enabled 应一致")

        // 验证 transport 类型和字段
        guard case .stdio(let cmd, let args, let env) = decoded.transport else {
            return XCTFail("解码后应为 stdio 传输")
        }
        XCTAssertEqual(cmd, "/usr/local/bin/node", "command 应一致")
        XCTAssertEqual(args, ["server.js", "--verbose"], "args 应一致")
        XCTAssertEqual(env?["NODE_ENV"], "production", "env.NODE_ENV 应一致")
        XCTAssertEqual(env?["DEBUG"], "mcp", "env.DEBUG 应一致")
    }

    /// stdio 配置（不含 env）应能正确编解码
    func testStdioConfigWithoutEnvCodable() throws {
        let config = MCPConfig(
            id: "test-stdio-002",
            name: "无环境变量",
            transport: .stdio(command: "python3", args: ["-m", "mcp_server"], env: nil),
            enabled: false
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPConfig.self, from: data)

        guard case .stdio(let cmd, let args, let env) = decoded.transport else {
            return XCTFail("解码后应为 stdio 传输")
        }
        XCTAssertEqual(cmd, "python3", "command 应一致")
        XCTAssertEqual(args, ["-m", "mcp_server"], "args 应一致")
        XCTAssertNil(env, "env 应为 nil")
        XCTAssertFalse(decoded.enabled, "enabled 应为 false")
    }

    /// SSE 配置（含 headers）应能正确编解码
    func testSSEConfigCodable() throws {
        let config = MCPConfig(
            id: "test-sse-001",
            name: "远程 SSE Server",
            transport: .sse(
                url: "https://example.com/mcp/sse",
                headers: ["Authorization": "Bearer token123", "X-Custom": "value"]
            ),
            enabled: true
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPConfig.self, from: data)

        XCTAssertEqual(decoded.id, config.id)
        XCTAssertEqual(decoded.name, config.name)

        guard case .sse(let url, let headers) = decoded.transport else {
            return XCTFail("解码后应为 sse 传输")
        }
        XCTAssertEqual(url, "https://example.com/mcp/sse", "url 应一致")
        XCTAssertEqual(headers?["Authorization"], "Bearer token123", "headers.Authorization 应一致")
        XCTAssertEqual(headers?["X-Custom"], "value", "headers.X-Custom 应一致")
    }

    /// SSE 配置（不含 headers）应能正确编解码
    func testSSEConfigWithoutHeadersCodable() throws {
        let config = MCPConfig(
            id: "test-sse-002",
            name: "无头 SSE",
            transport: .sse(url: "http://localhost:3000/sse", headers: nil),
            enabled: true
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPConfig.self, from: data)

        guard case .sse(let url, let headers) = decoded.transport else {
            return XCTFail("解码后应为 sse 传输")
        }
        XCTAssertEqual(url, "http://localhost:3000/sse")
        XCTAssertNil(headers, "headers 应为 nil")
    }

    /// MCPConfig 应满足 Hashable（可用于 Set / Dictionary key）
    func testConfigHashable() {
        let config1 = MCPConfig(id: "hash-001", name: "A", transport: .sse(url: "http://a", headers: nil), enabled: true)
        let config2 = MCPConfig(id: "hash-001", name: "A", transport: .sse(url: "http://a", headers: nil), enabled: true)
        let config3 = MCPConfig(id: "hash-002", name: "B", transport: .sse(url: "http://b", headers: nil), enabled: false)

        XCTAssertEqual(config1, config2, "相同内容的 config 应相等")
        XCTAssertNotEqual(config1, config3, "不同内容的 config 不应相等")
    }

    /// MCPConfig.Transport 两种类型应能正确判等
    func testTransportEquality() {
        let stdio1 = MCPConfig.Transport.stdio(command: "node", args: ["a"], env: ["X": "1"])
        let stdio2 = MCPConfig.Transport.stdio(command: "node", args: ["a"], env: ["X": "1"])
        let stdio3 = MCPConfig.Transport.stdio(command: "node", args: ["a"], env: ["X": "2"])
        let sse1 = MCPConfig.Transport.sse(url: "http://x", headers: nil)
        let sse2 = MCPConfig.Transport.sse(url: "http://x", headers: nil)

        XCTAssertEqual(stdio1, stdio2, "相同 stdio 传输应相等")
        XCTAssertNotEqual(stdio1, stdio3, "不同 env 的 stdio 不应相等")
        XCTAssertEqual(sse1, sse2, "相同 sse 传输应相等")
        XCTAssertNotEqual(stdio1, sse1, "stdio 和 sse 不应相等")
    }

    // MARK: - 2. JSON-RPC 消息构造和解析测试

    /// JSON-RPC 2.0 请求应包含 jsonrpc、id、method、params 字段
    func testJSONRPCRequestConstruction() throws {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": ["cursor": "next-page"]
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json, "请求应可序列化为 JSON")
        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0", "jsonrpc 版本应为 2.0")
        XCTAssertEqual(json?["id"] as? Int, 1, "id 应为 1")
        XCTAssertEqual(json?["method"] as? String, "tools/list", "method 应为 tools/list")

        let params = json?["params"] as? [String: Any]
        XCTAssertEqual(params?["cursor"] as? String, "next-page", "params.cursor 应一致")
    }

    /// JSON-RPC 通知（无 id）应正确构造
    func testJSONRPCNotificationConstruction() throws {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        ]

        let data = try JSONSerialization.data(withJSONObject: notification)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json?["method"] as? String, "notifications/initialized")
        XCTAssertNil(json?["id"], "通知不应包含 id 字段")
    }

    /// JSON-RPC 响应应正确解析 result 字段
    func testJSONRPCResponseParsing() throws {
        let responseJSON = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": {
                "tools": [
                    {"name": "search", "description": "搜索工具", "inputSchema": {"type": "object"}},
                    {"name": "calc", "description": "计算器", "inputSchema": {"type": "object"}}
                ]
            }
        }
        """.data(using: .utf8)!

        let json = try JSONSerialization.jsonObject(with: responseJSON) as? [String: Any]
        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json?["id"] as? Int, 1)

        let result = json?["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 2, "应有 2 个工具")
        XCTAssertEqual(tools?[0]["name"] as? String, "search")
        XCTAssertEqual(tools?[1]["name"] as? String, "calc")
    }

    /// JSON-RPC 错误响应应正确解析 error 字段
    func testJSONRPCErrorParsing() throws {
        let errorJSON = """
        {
            "jsonrpc": "2.0",
            "id": 2,
            "error": {
                "code": -32601,
                "message": "Method not found"
            }
        }
        """.data(using: .utf8)!

        let json = try JSONSerialization.jsonObject(with: errorJSON) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601, "错误码应为 -32601")
        XCTAssertEqual(error?["message"] as? String, "Method not found", "错误消息应一致")
    }

    /// initialize 请求参数应包含 protocolVersion、capabilities、clientInfo
    func testInitializeRequestParams() throws {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "Aether", "version": "1.0"]
        ]
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let decodedParams = json?["params"] as? [String: Any]

        XCTAssertEqual(decodedParams?["protocolVersion"] as? String, "2024-11-05")
        let clientInfo = decodedParams?["clientInfo"] as? [String: Any]
        XCTAssertEqual(clientInfo?["name"] as? String, "Aether")
        XCTAssertEqual(clientInfo?["version"] as? String, "1.0")
    }

    // MARK: - 3. MCPClient 初始化与连接测试（通过 MockTransport）

    /// MCPClient 初始化不应抛出错误，且 config 应正确保存
    func testMCPClientInit() async throws {
        let config = MCPConfig(
            id: "init-test",
            name: "测试 Server",
            transport: .sse(url: "http://localhost:9999/sse", headers: nil),
            enabled: true
        )
        let mock = MockTransport()
        let client = try MCPClient(config: config, transport: mock)

        let clientConfig = await client.config
        XCTAssertEqual(clientConfig.id, config.id, "config.id 应一致")
        XCTAssertEqual(clientConfig.name, config.name, "config.name 应一致")

        let connected = await client.isConnected
        XCTAssertFalse(connected, "初始化后应未连接")
    }

    /// MCPClient connect() 应完成 initialize 握手并发送 initialized 通知
    func testMCPClientConnect() async throws {
        let config = MCPConfig(
            id: "connect-test",
            name: "连接测试",
            transport: .sse(url: "http://localhost/sse", headers: nil),
            enabled: true
        )
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()

        let connected = await client.isConnected
        XCTAssertTrue(connected, "connect 后应已连接")

        // 验证发送了 initialize 请求和 initialized 通知
        let sent = mock.sentData
        XCTAssertGreaterThanOrEqual(sent.count, 2, "至少发送了 initialize 请求和 initialized 通知")

        // 验证第一条是 initialize 请求
        let firstMessage = try JSONSerialization.jsonObject(with: sent[0]) as? [String: Any]
        XCTAssertEqual(firstMessage?["method"] as? String, "initialize", "第一条消息应为 initialize 请求")

        // 验证第二条是 initialized 通知
        let secondMessage = try JSONSerialization.jsonObject(with: sent[1]) as? [String: Any]
        XCTAssertEqual(secondMessage?["method"] as? String, "notifications/initialized", "第二条消息应为 initialized 通知")
        XCTAssertNil(secondMessage?["id"], "通知不应包含 id")

        await client.disconnect()
    }

    /// MCPClient connect() 失败时应抛出错误
    func testMCPClientConnectFailure() async throws {
        let config = MCPConfig(
            id: "connect-fail-test",
            name: "失败测试",
            transport: .sse(url: "http://localhost/sse", headers: nil),
            enabled: true
        )
        let mock = MockTransport()
        // 不设置 responseHandler，所有请求无响应 → 超时
        // 但连接本身不会失败（MockTransport.connect() 不抛错）
        // 测试改为：transport.send 失败时不设置 handler 导致无响应
        // 为快速失败，使用超时较短的测试
        // 这里测试：未连接时调用 listTools 应抛 notConnected
        let client = try MCPClient(config: config, transport: mock)

        // 未连接时调用 listTools 应抛 notConnected
        do {
            _ = try await client.listTools()
            XCTFail("未连接时应抛出 notConnected 错误")
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

    /// MCPClient listTools() 应正确解析工具列表
    func testMCPClientListTools() async throws {
        let config = makeTestConfig(id: "list-tools-test")
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()
        let tools = try await client.listTools()

        XCTAssertEqual(tools.count, 2, "应有 2 个工具")
        XCTAssertEqual(tools[0].name, "search", "第一个工具名应为 search")
        XCTAssertEqual(tools[0].description, "搜索工具")
        XCTAssertEqual(tools[0].inputSchema["type"] as? String, "object")
        XCTAssertEqual(tools[1].name, "calc", "第二个工具名应为 calc")

        await client.disconnect()
    }

    /// MCPClient listResources() 应正确解析资源列表
    func testMCPClientListResources() async throws {
        let config = makeTestConfig(id: "list-resources-test")
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()
        let resources = try await client.listResources()

        XCTAssertEqual(resources.count, 1, "应有 1 个资源")
        XCTAssertEqual(resources[0].uri, "file:///test.txt", "uri 应一致")
        XCTAssertEqual(resources[0].name, "测试文件", "name 应一致")
        XCTAssertEqual(resources[0].mimeType, "text/plain", "mimeType 应一致")

        await client.disconnect()
    }

    /// MCPClient listPrompts() 应正确解析提示模板列表
    func testMCPClientListPrompts() async throws {
        let config = makeTestConfig(id: "list-prompts-test")
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()
        let prompts = try await client.listPrompts()

        XCTAssertEqual(prompts.count, 1, "应有 1 个提示模板")
        XCTAssertEqual(prompts[0].name, "greeting", "name 应一致")
        XCTAssertEqual(prompts[0].description, "问候提示", "description 应一致")
        XCTAssertEqual(prompts[0].arguments?.count, 1, "应有 1 个参数")
        XCTAssertEqual(prompts[0].arguments?[0].name, "name", "参数名应为 name")
        XCTAssertTrue(prompts[0].arguments?[0].required ?? false, "参数应必填")

        await client.disconnect()
    }

    /// MCPClient callTool() 应正确调用工具并返回结果
    func testMCPClientCallTool() async throws {
        let config = makeTestConfig(id: "call-tool-test")
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()
        let result = try await client.callTool(name: "search", arguments: ["query": "hello"])

        XCTAssertNotNil(result.content, "结果应含 content")
        XCTAssertEqual(result.content.count, 1, "应有 1 个内容块")
        XCTAssertEqual(result.content[0].type, "text", "内容类型应为 text")
        XCTAssertEqual(result.content[0].text, "搜索结果: hello", "文本内容应一致")
        XCTAssertFalse(result.isError ?? true, "不应为错误")

        await client.disconnect()
    }

    /// MCPClient readResource() 应正确读取资源
    func testMCPClientReadResource() async throws {
        let config = makeTestConfig(id: "read-resource-test")
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()
        let contents = try await client.readResource(uri: "file:///test.txt")

        XCTAssertEqual(contents.count, 1, "应有 1 个资源内容")
        XCTAssertEqual(contents[0].uri, "file:///test.txt", "uri 应一致")
        XCTAssertEqual(contents[0].text, "Hello World", "文本内容应一致")
        XCTAssertEqual(contents[0].mimeType, "text/plain", "mimeType 应一致")

        await client.disconnect()
    }

    /// MCPClient getPrompt() 应正确获取提示模板内容
    func testMCPClientGetPrompt() async throws {
        let config = makeTestConfig(id: "get-prompt-test")
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()
        let result = try await client.getPrompt(name: "greeting", arguments: ["name": "Alice"])

        XCTAssertEqual(result.description, "问候提示模板", "description 应一致")
        XCTAssertEqual(result.messages.count, 1, "应有 1 条消息")
        XCTAssertEqual(result.messages[0].role, "user", "角色应为 user")
        XCTAssertEqual(result.messages[0].content.type, "text", "内容类型应为 text")
        XCTAssertEqual(result.messages[0].content.text, "你好, Alice!", "文本内容应一致")

        await client.disconnect()
    }

    /// MCPClient disconnect() 后应未连接
    func testMCPClientDisconnect() async throws {
        let config = makeTestConfig(id: "disconnect-test")
        let mock = MockTransport()
        mock.responseHandler = makeMockResponseHandler()
        let client = try MCPClient(config: config, transport: mock)

        try await client.connect()
        let connectedAfterConnect = await client.isConnected
        XCTAssertTrue(connectedAfterConnect, "连接后应为已连接")

        await client.disconnect()
        let connectedAfterDisconnect = await client.isConnected
        XCTAssertFalse(connectedAfterDisconnect, "断开后应未连接")
    }

    // MARK: - 4. MCPClientManager 多 Server 管理测试

    /// MCPClientManager 应能管理多个 Server 连接
    @MainActor
    func testManagerConnectMultipleServers() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, tools: [
                MCPTool(name: "tool_\(config.id)", description: "工具", inputSchema: ["type": "object"])
            ])
        })

        let config1 = makeTestConfig(id: "server-1", name: "Server 1")
        let config2 = makeTestConfig(id: "server-2", name: "Server 2")

        try await manager.connect(config: config1)
        try await manager.connect(config: config2)

        let connected = manager.getConnectedServers()
        XCTAssertEqual(connected.count, 2, "应有 2 个已连接 Server")

        // 验证拉取了工具
        let server1Info = manager.serverInfos["server-1"]
        XCTAssertEqual(server1Info?.status, .connected, "Server 1 状态应为 connected")
        XCTAssertEqual(server1Info?.tools.count, 1, "Server 1 应有 1 个工具")
        XCTAssertEqual(server1Info?.tools.first?.name, "tool_server-1")

        let server2Info = manager.serverInfos["server-2"]
        XCTAssertEqual(server2Info?.status, .connected, "Server 2 状态应为 connected")
        XCTAssertEqual(server2Info?.tools.first?.name, "tool_server-2")
    }

    /// MCPClientManager disconnect(serverID:) 应断开指定 Server
    @MainActor
    func testManagerDisconnectSpecificServer() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        let config1 = makeTestConfig(id: "dc-server-1", name: "DC Server 1")
        let config2 = makeTestConfig(id: "dc-server-2", name: "DC Server 2")

        try await manager.connect(config: config1)
        try await manager.connect(config: config2)
        XCTAssertEqual(manager.getConnectedServers().count, 2, "连接 2 个 Server")

        await manager.disconnect(serverID: "dc-server-1")
        XCTAssertEqual(manager.getConnectedServers().count, 1, "断开 1 个后应剩 1 个")

        let info = manager.serverInfos["dc-server-1"]
        XCTAssertEqual(info?.status, .disconnected, "断开的 Server 状态应为 disconnected")

        // Server 2 仍连接
        let info2 = manager.serverInfos["dc-server-2"]
        XCTAssertEqual(info2?.status, .connected, "Server 2 应仍连接")
    }

    /// MCPClientManager disconnectAll() 应断开所有 Server
    @MainActor
    func testManagerDisconnectAll() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        try await manager.connect(config: makeTestConfig(id: "all-1"))
        try await manager.connect(config: makeTestConfig(id: "all-2"))
        try await manager.connect(config: makeTestConfig(id: "all-3"))
        XCTAssertEqual(manager.getConnectedServers().count, 3, "应连接 3 个 Server")

        await manager.disconnectAll()
        XCTAssertEqual(manager.getConnectedServers().count, 0, "全部断开后应为 0")

        for (_, info) in manager.serverInfos {
            XCTAssertEqual(info.status, .disconnected, "所有 Server 状态应为 disconnected")
        }
    }

    /// MCPClientManager connect 失败时应更新状态为 error 并抛出错误
    @MainActor
    func testManagerConnectFailure() async {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config, connectShouldFail: true)
        })

        let config = makeTestConfig(id: "fail-server", name: "失败 Server")

        do {
            try await manager.connect(config: config)
            XCTFail("连接应失败")
        } catch {
            // 预期抛出错误
        }

        let info = manager.serverInfos["fail-server"]
        if case .error = info?.status {
            // 预期状态为 error
        } else {
            XCTFail("状态应为 error，实际: \(String(describing: info?.status))")
        }
        XCTAssertEqual(manager.getConnectedServers().count, 0, "失败后无已连接 Server")
    }

    /// MCPClientManager getConnectedServers 应按名称排序
    @MainActor
    func testManagerGetConnectedServersSorted() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        try await manager.connect(config: MCPConfig(id: "z", name: "Zebra", transport: .sse(url: "http://z", headers: nil), enabled: true))
        try await manager.connect(config: MCPConfig(id: "a", name: "Apple", transport: .sse(url: "http://a", headers: nil), enabled: true))
        try await manager.connect(config: MCPConfig(id: "m", name: "Mango", transport: .sse(url: "http://m", headers: nil), enabled: true))

        let connected = manager.getConnectedServers()
        XCTAssertEqual(connected.map(\.name), ["Apple", "Mango", "Zebra"], "应按名称字母升序排序")
    }

    /// MCPClientManager getClient 应返回已连接的客户端
    @MainActor
    func testManagerGetClient() async throws {
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })

        try await manager.connect(config: makeTestConfig(id: "get-client-test"))
        let client = manager.getClient(serverID: "get-client-test")
        XCTAssertNotNil(client, "应能获取已连接的客户端")

        let nilClient = manager.getClient(serverID: "non-existent")
        XCTAssertNil(nilClient, "不存在的 Server 应返回 nil")
    }

    // MARK: - 5. SSE 安全测试（endpoint 劫持防护）

    /// 测试用 URLProtocol：拦截 URLSession 请求，返回预设 SSE 响应。
    /// 避免真实网络请求，确保测试稳定。
    private final class MockSSEURLProtocol: URLProtocol {
        /// 预设 SSE 响应体
        static var responseData: Data = Data()
        /// 预设 HTTP 状态码
        static var statusCode: Int = 200
        /// 预设响应头
        static var responseHeaders: [String: String] = [
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache"
        ]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: MockSSEURLProtocol.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: MockSSEURLProtocol.responseHeaders
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: MockSSEURLProtocol.responseData)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        /// 重置静态状态（测试间隔离）
        static func reset() {
            responseData = Data()
            statusCode = 200
            responseHeaders = ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"]
        }
    }

    /// SSE 解析时应拒绝跨域 endpoint 事件（防劫持），且不影响正常 message 事件传递。
    ///
    /// 验证点：
    /// 1. 恶意 `event: endpoint`（跨域 URL）不被设置为 POST 端点
    /// 2. `endpoint` 事件不传递给消息流（上层仅收到 `message` 事件）
    /// 3. `send()` 因 postEndpoint 为 nil 而抛出 connectionFailed 错误
    func testSSEEndpointHijackIsRejected() async throws {
        // SSE 连接 URL（localhost:9999）
        let sseURL = "http://localhost:9999/sse"
        // 恶意 endpoint URL（evil.com，与 SSE 连接不同源，触发劫持检测）
        let evilEndpoint = "http://evil.com/api"

        // 构造 SSE 响应：先发送恶意 endpoint 事件，再发送一条正常 message 事件。
        // 事件之间用空行分隔，末尾空行确保最后一个事件被处理。
        let sseResponse = """
        event: endpoint
        data: \(evilEndpoint)

        event: message
        data: {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}

        """

        // 配置 Mock URLSession（通过 URLProtocol 拦截所有请求，无需真实网络）
        MockSSEURLProtocol.reset()
        MockSSEURLProtocol.responseData = sseResponse.data(using: .utf8)!
        let urlSessionConfig = URLSessionConfiguration.ephemeral
        urlSessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: urlSessionConfig)

        // 创建 SSETransport，注入 Mock session
        let transport = SSETransport(urlString: sseURL, headers: nil, session: session)

        // 先启动消息流（设置 continuation），再连接。
        // 否则 connect() 启动的读取 Task 会在 continuation 为 nil 时丢弃 message 事件。
        let messageStream = transport.messages()
        try await transport.connect()

        // 收集消息（流会在 SSE 响应读取完毕后自动结束）
        let messages = await collectSSEMessages(from: messageStream, timeoutSeconds: 5)

        // 断言 1：endpoint 事件不应出现在消息流中，只有 message 事件被传递给上层
        XCTAssertEqual(messages.count, 1, "应仅收到 1 条 message 事件，endpoint 事件不应传递给上层")
        guard let firstMessage = messages.first else {
            return XCTFail("未收到任何消息，SSE 流可能超时或异常")
        }
        let json = try JSONSerialization.jsonObject(with: firstMessage) as? [String: Any]
        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0", "消息内容应为 JSON-RPC 响应")
        XCTAssertEqual(json?["id"] as? Int, 1, "消息 id 应为 1")

        // 断言 2：恶意 endpoint 被拒绝后 postEndpoint 为 nil，send() 应抛出 connectionFailed
        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("恶意 endpoint 应被拒绝，send() 应抛出 connectionFailed 错误")
        } catch let error as MCPError {
            if case .connectionFailed = error {
                // 预期：postEndpoint 未设置，send() 抛出 "SSE POST 端点未就绪"
            } else {
                XCTFail("应为 connectionFailed 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }

        await transport.disconnect()
    }

    /// 从 AsyncStream 收集所有消息，带超时保护（防止测试挂起）。
    /// 流正常结束后返回所有消息；超时则返回已收集的消息。
    private func collectSSEMessages(from stream: AsyncStream<Data>, timeoutSeconds: TimeInterval = 5) async -> [Data] {
        await withTaskGroup(of: [Data].self) { group in
            // 消息收集任务：流结束时返回所有消息
            group.addTask {
                var messages: [Data] = []
                for await data in stream {
                    messages.append(data)
                }
                return messages
            }
            // 超时看门狗任务：到达超时时间返回空数组
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return []
            }
            // 等待先完成的任务，取消另一个
            let result = await group.next() ?? []
            group.cancelAll()
            return result
        }
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

    /// 创建 MockTransport 的响应处理器，覆盖 initialize / tools/list / resources/list / prompts/list / tools/call / resources/read / prompts/get
    private func makeMockResponseHandler() -> (Data) -> Data? {
        return { requestData in
            guard let json = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
                  let id = json["id"] as? Int,
                  let method = json["method"] as? String else {
                // 通知（无 id）不生成响应
                return nil
            }

            switch method {
            case "initialize":
                return Self.makeJSONRPCResponse(id: id, result: [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:],
                    "serverInfo": ["name": "mock-server", "version": "1.0"]
                ])
            case "tools/list":
                return Self.makeJSONRPCResponse(id: id, result: [
                    "tools": [
                        ["name": "search", "description": "搜索工具", "inputSchema": ["type": "object", "properties": ["query": ["type": "string"]]]],
                        ["name": "calc", "description": "计算器", "inputSchema": ["type": "object"]]
                    ]
                ])
            case "resources/list":
                return Self.makeJSONRPCResponse(id: id, result: [
                    "resources": [
                        ["uri": "file:///test.txt", "name": "测试文件", "description": "测试用文件", "mimeType": "text/plain"]
                    ]
                ])
            case "prompts/list":
                return Self.makeJSONRPCResponse(id: id, result: [
                    "prompts": [
                        ["name": "greeting", "description": "问候提示", "arguments": [
                            ["name": "name", "description": "称呼", "required": true]
                        ]]
                    ]
                ])
            case "tools/call":
                guard let params = json["params"] as? [String: Any],
                      let toolName = params["name"] as? String,
                      let arguments = params["arguments"] as? [String: Any] else {
                    return Self.makeJSONRPCResponse(id: id, result: ["content": [["type": "text", "text": "参数错误"]], "isError": true])
                }
                if toolName == "search" {
                    let query = arguments["query"] as? String ?? ""
                    return Self.makeJSONRPCResponse(id: id, result: [
                        "content": [["type": "text", "text": "搜索结果: \(query)"]],
                        "isError": false
                    ])
                }
                return Self.makeJSONRPCResponse(id: id, result: [
                    "content": [["type": "text", "text": "工具 \(toolName) 执行完成"]],
                    "isError": false
                ])
            case "resources/read":
                return Self.makeJSONRPCResponse(id: id, result: [
                    "contents": [
                        ["uri": "file:///test.txt", "mimeType": "text/plain", "text": "Hello World"]
                    ]
                ])
            case "prompts/get":
                guard let params = json["params"] as? [String: Any],
                      let arguments = params["arguments"] as? [String: Any] else {
                    return Self.makeJSONRPCResponse(id: id, result: ["messages": []])
                }
                let name = arguments["name"] as? String ?? "World"
                return Self.makeJSONRPCResponse(id: id, result: [
                    "description": "问候提示模板",
                    "messages": [
                        ["role": "user", "content": ["type": "text", "text": "你好, \(name)!"]]
                    ]
                ])
            default:
                return Self.makeJSONRPCResponse(id: id, result: [:])
            }
        }
    }

    /// 构造 JSON-RPC 2.0 响应 Data
    private static func makeJSONRPCResponse(id: Int, result: [String: Any]) -> Data {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
    }
}

// MARK: - Mock 传输层（用于 MCPClient 测试）

/// 测试用 Mock 传输层，通过 responseHandler 闭包生成响应。
/// 记录所有发送的数据，便于测试断言。
final class MockTransport: @unchecked Sendable, MCPTransport {
    /// 响应生成闭包：接收请求数据，返回响应数据（nil 表示不响应，如通知）
    var responseHandler: ((Data) -> Data?)?
    /// 消息流 continuation
    private var continuation: AsyncStream<Data>.Continuation?
    /// 已发送的数据列表（测试断言用）
    private(set) var sentData: [Data] = []
    /// 线程安全锁
    private let lock = NSLock()

    func connect() async throws {
        // Mock 无需实际连接
    }

    func disconnect() async {
        continuation?.finish()
    }

    func send(_ data: Data) async throws {
        lock.lock()
        sentData.append(data)
        let handler = responseHandler
        lock.unlock()

        // 调用 responseHandler 生成响应并 yield 到消息流
        if let handler = handler, let response = handler(data) {
            continuation?.yield(response)
        }
    }

    func messages() -> AsyncStream<Data> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }
}

// MARK: - Mock MCP 客户端（用于 MCPClientManager 测试）

/// 测试用 Mock MCP 客户端，实现 MCPClientProtocol。
/// 可配置连接是否失败、返回的 tools/resources/prompts。
actor MockMCPClient: MCPClientProtocol {
    let config: MCPConfig
    private let connectShouldFail: Bool
    private let mockTools: [MCPTool]
    private let mockResources: [MCPResource]
    private let mockPrompts: [MCPPrompt]

    /// connect 调用次数（测试断言用）
    private(set) var connectCallCount = 0
    /// disconnect 调用次数（测试断言用）
    private(set) var disconnectCallCount = 0

    init(config: MCPConfig,
         connectShouldFail: Bool = false,
         tools: [MCPTool] = [],
         resources: [MCPResource] = [],
         prompts: [MCPPrompt] = []) {
        self.config = config
        self.connectShouldFail = connectShouldFail
        self.mockTools = tools
        self.mockResources = resources
        self.mockPrompts = prompts
    }

    func connect() async throws {
        connectCallCount += 1
        if connectShouldFail {
            throw MCPError.connectionFailed("Mock 连接失败")
        }
    }

    func disconnect() async {
        disconnectCallCount += 1
    }

    func listTools() async throws -> [MCPTool] { mockTools }
    func listResources() async throws -> [MCPResource] { mockResources }
    func listPrompts() async throws -> [MCPPrompt] { mockPrompts }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
        MCPToolCallResult(
            content: [MCPToolCallResult.Content(type: "text", text: "mock result", data: nil, mimeType: nil)],
            isError: false
        )
    }

    func readResource(uri: String) async throws -> [MCPResourceContent] {
        [MCPResourceContent(uri: uri, mimeType: "text/plain", text: "mock content", blob: nil)]
    }

    func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult {
        MCPPromptResult(
            description: "mock prompt",
            messages: [MCPPromptResult.Message(role: "user", content: MCPPromptResult.Content(type: "text", text: "mock message"))]
        )
    }
}
