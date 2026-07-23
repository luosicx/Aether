import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// MCPServer 单元测试（v1.1 Phase A: 反向暴露）。
///
/// 覆盖范围：
/// 1. start/stop 生命周期
/// 2. initialize 握手响应（serverInfo / capabilities / protocolVersion）
/// 3. tools/list 返回白名单工具
/// 4. tools/call 正确路由并返回结果
/// 5. resources/list 返回资源列表
/// 6. prompts/list 返回 Prompts 列表
/// 7. 工具白名单过滤（非白名单工具不暴露）
///
/// 使用 ServerMockTransport 注入请求并捕获响应，模拟外部 MCP 客户端调用 Aether Server。
@MainActor
final class MCPServerTests: XCTestCase {
    /// 测试用 transport（注入请求、捕获响应）
    private var transport: ServerMockTransport!
    /// 待测 MCPServer
    private var server: MCPServer!

    override func setUp() async throws {
        try await super.setUp()
        transport = ServerMockTransport()
        server = MCPServer(transport: transport)
    }

    override func tearDown() async throws {
        await server?.stop()
        server = nil
        transport = nil
        try await super.tearDown()
    }

    // MARK: - 1. 生命周期测试

    /// start 应启动 Server，stop 应停止 Server
    func testStartStopLifecycle() async throws {
        try await server.start()
        let runningAfterStart = await server.isRunning
        XCTAssertTrue(runningAfterStart, "start 后 isRunning 应为 true")

        await server.stop()
        let runningAfterStop = await server.isRunning
        XCTAssertFalse(runningAfterStop, "stop 后 isRunning 应为 false")
    }

    /// 重复 start 应为 no-op（不抛错）
    func testDoubleStartIsNoOp() async throws {
        try await server.start()
        try await server.start() // 不应抛错
        let running = await server.isRunning
        XCTAssertTrue(running)
    }

    /// 重复 stop 应为 no-op（不抛错）
    func testDoubleStopIsNoOp() async throws {
        try await server.start()
        await server.stop()
        await server.stop() // 不应抛错
        let running = await server.isRunning
        XCTAssertFalse(running)
    }

    // MARK: - 2. initialize 握手响应

    /// initialize 应返回 serverInfo（name=aether, version=1.1.0）+ capabilities + protocolVersion
    func testInitializeResponse() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "initialize", id: 1)
        XCTAssertNotNil(response, "应收到响应")

        let result = response?["result"] as? [String: Any]
        XCTAssertNotNil(result, "响应应包含 result")

        XCTAssertEqual(result?["protocolVersion"] as? String, "2024-11-05", "协议版本应为 2024-11-05")

        let serverInfo = result?["serverInfo"] as? [String: Any]
        XCTAssertEqual(serverInfo?["name"] as? String, "aether", "serverInfo.name 应为 aether")
        XCTAssertEqual(serverInfo?["version"] as? String, "1.1.0", "serverInfo.version 应为 1.1.0")

        let capabilities = result?["capabilities"] as? [String: Any]
        XCTAssertNotNil(capabilities?["tools"], "capabilities 应包含 tools")
        XCTAssertNotNil(capabilities?["resources"], "capabilities 应包含 resources")
        XCTAssertNotNil(capabilities?["prompts"], "capabilities 应包含 prompts")
    }

    /// initialize 响应应包含正确的 jsonrpc 版本和 id
    func testInitializeResponseFormat() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "initialize", id: 42)
        XCTAssertEqual(response?["jsonrpc"] as? String, "2.0", "jsonrpc 版本应为 2.0")
        XCTAssertEqual(response?["id"] as? Int, 42, "响应 id 应与请求 id 一致")
    }

    // MARK: - 3. tools/list 测试

    /// tools/list 应返回默认白名单中的 14 个跨平台工具
    func testToolsListReturnsDefaultWhitelist() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "tools/list", id: 2)
        XCTAssertNotNil(response)

        let result = response?["result"] as? [String: Any]
        let toolsArray = result?["tools"] as? [[String: Any]]
        XCTAssertNotNil(toolsArray, "result 应包含 tools 数组")

        let toolNames = toolsArray?.compactMap { $0["name"] as? String } ?? []
        XCTAssertEqual(toolNames.count, MCPServerDefaultTools.crossPlatform.count, "工具数量应与默认白名单一致")

        // 验证白名单中的工具都出现在响应中
        for expectedName in MCPServerDefaultTools.crossPlatform {
            XCTAssertTrue(toolNames.contains(expectedName), "工具 \(expectedName) 应在 tools/list 响应中")
        }
    }

    /// tools/list 返回的工具应包含 name / description / inputSchema 字段
    func testToolsListToolFormat() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "tools/list", id: 3)
        let result = response?["result"] as? [String: Any]
        let toolsArray = result?["tools"] as? [[String: Any]] ?? []

        // 取一个已知存在的工具（calculate）验证字段完整性
        let calcTool = toolsArray.first { ($0["name"] as? String) == "calculate" }
        XCTAssertNotNil(calcTool, "calculate 工具应在列表中")
        XCTAssertNotNil(calcTool?["description"], "工具应包含 description")
        XCTAssertNotNil(calcTool?["inputSchema"], "工具应包含 inputSchema")
    }

    /// tools/list 应按自定义白名单过滤（仅返回注册的工具）
    func testToolsListWithCustomWhitelist() async throws {
        let customWhitelist = ["calculate", "get_current_time"]
        await server.registerTools(customWhitelist)
        try await server.start()

        let response = await sendRequestAndWait(method: "tools/list", id: 4)
        let result = response?["result"] as? [String: Any]
        let toolsArray = result?["tools"] as? [[String: Any]] ?? []

        let toolNames = toolsArray.compactMap { $0["name"] as? String }
        XCTAssertEqual(toolNames.count, 2, "自定义白名单应仅返回 2 个工具")
        XCTAssertTrue(toolNames.contains("calculate"))
        XCTAssertTrue(toolNames.contains("get_current_time"))
    }

    /// tools/list 空白名单应返回 0 个工具
    func testToolsListWithEmptyWhitelist() async throws {
        await server.registerTools([])
        try await server.start()

        let response = await sendRequestAndWait(method: "tools/list", id: 5)
        let result = response?["result"] as? [String: Any]
        let toolsArray = result?["tools"] as? [[String: Any]] ?? []
        XCTAssertTrue(toolsArray.isEmpty, "空白名单应返回空工具列表")
    }

    // MARK: - 4. tools/call 测试

    /// tools/call 应正确路由到 ToolRegistry 并返回执行结果
    func testToolsCallExecutesTool() async throws {
        try await server.start()

        let params: [String: Any] = [
            "name": "calculate",
            "arguments": ["expression": "1 + 2"]
        ]
        let response = await sendRequestAndWait(method: "tools/call", params: params, id: 6)

        let result = response?["result"] as? [String: Any]
        XCTAssertNotNil(result, "tools/call 应返回 result")

        let content = result?["content"] as? [[String: Any]]
        XCTAssertNotNil(content, "result 应包含 content 数组")
        XCTAssertEqual(content?.first?["type"] as? String, "text", "content 类型应为 text")

        let isError = result?["isError"] as? Bool
        XCTAssertEqual(isError, false, "成功执行时 isError 应为 false")

        let text = content?.first?["text"] as? String
        XCTAssertNotNil(text, "content 应包含 text 字段")
        XCTAssertTrue(text?.contains("3") == true, "1+2 的结果应包含 3")
    }

    /// tools/call 调用非白名单工具应返回 isError=true
    func testToolsCallNonWhitelistedToolReturnsError() async throws {
        // 仅注册 calculate 到白名单
        await server.registerTools(["calculate"])
        try await server.start()

        let params: [String: Any] = [
            "name": "get_current_time", // 不在白名单中
            "arguments": [:]
        ]
        let response = await sendRequestAndWait(method: "tools/call", params: params, id: 7)

        let result = response?["result"] as? [String: Any]
        let isError = result?["isError"] as? Bool
        XCTAssertEqual(isError, true, "非白名单工具应返回 isError=true")
    }

    /// tools/call 缺少 name 参数应返回错误响应
    func testToolsCallMissingNameParameter() async throws {
        try await server.start()

        let params: [String: Any] = ["arguments": [:]]
        let response = await sendRequestAndWait(method: "tools/call", params: params, id: 8)

        // 缺少 name 应触发 error 响应
        XCTAssertNotNil(response?["error"], "缺少 name 参数应返回 error")
    }

    // MARK: - 5. resources/list 测试

    /// resources/list 应返回注册的资源列表
    func testResourcesListReturnsRegisteredResources() async throws {
        let testResources = [
            MCPResource(uri: "file:///test.txt", name: "测试文件", description: "测试资源", mimeType: "text/plain"),
            MCPResource(uri: "file:///doc.md", name: "文档", description: nil, mimeType: nil)
        ]
        await server.registerResources(testResources)
        try await server.start()

        let response = await sendRequestAndWait(method: "resources/list", id: 9)
        let result = response?["result"] as? [String: Any]
        let resourcesArray = result?["resources"] as? [[String: Any]] ?? []

        XCTAssertEqual(resourcesArray.count, 2, "应返回 2 个资源")
        XCTAssertEqual(resourcesArray[0]["uri"] as? String, "file:///test.txt")
        XCTAssertEqual(resourcesArray[0]["name"] as? String, "测试文件")
        XCTAssertEqual(resourcesArray[0]["description"] as? String, "测试资源")
        XCTAssertEqual(resourcesArray[0]["mimeType"] as? String, "text/plain")
    }

    /// resources/list 空列表应返回空数组
    func testResourcesListEmpty() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "resources/list", id: 10)
        let result = response?["result"] as? [String: Any]
        let resourcesArray = result?["resources"] as? [[String: Any]] ?? []
        XCTAssertTrue(resourcesArray.isEmpty, "无资源时应返回空数组")
    }

    // MARK: - 6. prompts/list 测试

    /// prompts/list 应返回注册的 Prompts 列表
    func testPromptsListReturnsRegisteredPrompts() async throws {
        let testPrompts = [
            MCPPrompt(
                name: "greeting",
                description: "问候提示",
                arguments: [
                    MCPPromptArgument(name: "user_name", description: "用户名", required: true)
                ]
            ),
            MCPPrompt(name: "summary", description: "摘要提示", arguments: nil)
        ]
        await server.registerPrompts(testPrompts)
        try await server.start()

        let response = await sendRequestAndWait(method: "prompts/list", id: 11)
        let result = response?["result"] as? [String: Any]
        let promptsArray = result?["prompts"] as? [[String: Any]] ?? []

        XCTAssertEqual(promptsArray.count, 2, "应返回 2 个 Prompts")
        XCTAssertEqual(promptsArray[0]["name"] as? String, "greeting")
        XCTAssertEqual(promptsArray[0]["description"] as? String, "问候提示")

        let args = promptsArray[0]["arguments"] as? [[String: Any]] ?? []
        XCTAssertEqual(args.count, 1)
        XCTAssertEqual(args[0]["name"] as? String, "user_name")
        XCTAssertEqual(args[0]["required"] as? Bool, true)
    }

    /// prompts/list 空列表应返回空数组
    func testPromptsListEmpty() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "prompts/list", id: 12)
        let result = response?["result"] as? [String: Any]
        let promptsArray = result?["prompts"] as? [[String: Any]] ?? []
        XCTAssertTrue(promptsArray.isEmpty, "无 Prompts 时应返回空数组")
    }

    // MARK: - 7. 注册接口测试

    /// registerTools 应更新白名单，后续 tools/list 反映新白名单
    func testRegisterToolsUpdatesWhitelist() async throws {
        try await server.start()

        // 初始白名单应有 14 个工具
        let response1 = await sendRequestAndWait(method: "tools/list", id: 13)
        let result1 = response1?["result"] as? [String: Any]
        let count1 = (result1?["tools"] as? [[String: Any]])?.count ?? 0
        XCTAssertEqual(count1, MCPServerDefaultTools.crossPlatform.count)

        // 更新白名单
        await server.registerTools(["calculate"])

        // 重置已发送数据，避免读到旧响应
        transport.resetSentData()
        let response2 = await sendRequestAndWait(method: "tools/list", id: 14)
        let result2 = response2?["result"] as? [String: Any]
        let toolsArray = (result2?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(toolsArray.count, 1, "更新白名单后应仅返回 1 个工具")
        XCTAssertEqual(toolsArray[0]["name"] as? String, "calculate")
    }

    /// registerResources 应更新资源列表
    func testRegisterResourcesUpdatesList() async throws {
        try await server.start()

        // 初始无资源
        let response1 = await sendRequestAndWait(method: "resources/list", id: 15)
        let result1 = response1?["result"] as? [String: Any]
        let count1 = (result1?["resources"] as? [[String: Any]])?.count ?? 0
        XCTAssertEqual(count1, 0)

        // 注册资源
        let resources = [MCPResource(uri: "file:///new.txt", name: "新文件", description: nil, mimeType: nil)]
        await server.registerResources(resources)

        transport.resetSentData()
        let response2 = await sendRequestAndWait(method: "resources/list", id: 16)
        let result2 = response2?["result"] as? [String: Any]
        let count2 = (result2?["resources"] as? [[String: Any]])?.count ?? 0
        XCTAssertEqual(count2, 1)
    }

    /// registerPrompts 应更新 Prompts 列表
    func testRegisterPromptsUpdatesList() async throws {
        try await server.start()

        // 初始无 Prompts
        let response1 = await sendRequestAndWait(method: "prompts/list", id: 17)
        let result1 = response1?["result"] as? [String: Any]
        let count1 = (result1?["prompts"] as? [[String: Any]])?.count ?? 0
        XCTAssertEqual(count1, 0)

        // 注册 Prompts
        let prompts = [MCPPrompt(name: "test_prompt", description: "测试", arguments: nil)]
        await server.registerPrompts(prompts)

        transport.resetSentData()
        let response2 = await sendRequestAndWait(method: "prompts/list", id: 18)
        let result2 = response2?["result"] as? [String: Any]
        let count2 = (result2?["prompts"] as? [[String: Any]])?.count ?? 0
        XCTAssertEqual(count2, 1)
    }

    // MARK: - 8. 未知方法测试

    /// 未知方法应返回 JSON-RPC error 响应
    func testUnknownMethodReturnsError() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "unknown/method", id: 19)
        XCTAssertNotNil(response?["error"], "未知方法应返回 error")
        let error = response?["error"] as? [String: Any]
        XCTAssertNotNil(error?["code"], "error 应包含 code")
        XCTAssertNotNil(error?["message"], "error 应包含 message")
    }

    // MARK: - 9. ping 与通知测试

    /// ping 方法应返回空 result
    func testPingReturnsEmptyResult() async throws {
        try await server.start()

        let response = await sendRequestAndWait(method: "ping", id: 20)
        XCTAssertNotNil(response, "ping 应返回响应")
        XCTAssertNotNil(response?["result"], "ping 应返回 result")
        let result = response?["result"] as? [String: Any]
        XCTAssertEqual(result?.count, 0, "ping result 应为空字典")
    }

    /// notifications/initialized 无 id 通知不应返回响应
    func testNotificationDoesNotReturnResponse() async throws {
        try await server.start()

        transport.resetSentData()

        // 发送无 id 的通知（JSON-RPC 通知格式）
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
            // 注意：无 id 字段
        ]
        let data = try JSONSerialization.data(withJSONObject: notification)
        transport.inject(data)

        // 等待 500ms 确认无响应
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(transport.sentData.isEmpty, "通知（无 id）不应返回响应")
    }

    // MARK: - 10. 非 JSON / 非 JSON-RPC 请求测试

    /// 非 JSON 数据应被忽略，不返回响应
    func testInvalidJSONReturnsNoResponse() async throws {
        try await server.start()

        transport.resetSentData()

        let invalidData = "not a json string {{{".data(using: .utf8)!
        transport.inject(invalidData)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(transport.sentData.isEmpty, "非 JSON 数据不应返回响应")
    }

    /// JSON 但缺少 method 字段应被忽略
    func testNonJSONRPCRequestReturnsNoResponse() async throws {
        try await server.start()

        transport.resetSentData()

        let nonRPC: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 21
            // 缺少 method 字段
        ]
        let data = try JSONSerialization.data(withJSONObject: nonRPC)
        transport.inject(data)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(transport.sentData.isEmpty, "缺少 method 的 JSON 不应返回响应")
    }

    // MARK: - 11. tools/call 参数缺失与执行错误测试

    /// tools/call 不传 params 应返回错误（-32602）
    func testToolsCallWithMissingParamsReturnsError() async throws {
        try await server.start()

        // tools/call 请求不带 params 字段
        let response = await sendRequestAndWaitNoParams(method: "tools/call", id: 22)
        XCTAssertNotNil(response?["error"], "tools/call 缺少 params 应返回 error")
        let error = response?["error"] as? [String: Any]
        let code = error?["code"] as? Int
        XCTAssertEqual(code, -32602, "缺少 params 应返回 -32602 Invalid params")
    }

    /// 白名单工具执行抛错时应返回 isError=true
    func testToolsCallExecutionErrorReturnsIsError() async throws {
        try await server.start()

        // 调用 calculate 工具，传入无效表达式触发执行错误
        let response = await sendRequestAndWait(
            method: "tools/call",
            params: ["name": "calculate", "arguments": ["expression": "###invalid###"]],
            id: 23
        )
        XCTAssertNotNil(response?["result"], "执行错误应返回 result（非 error）")
        let result = response?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, true, "执行错误时 isError 应为 true")
        let content = result?["content"] as? [[String: Any]]
        XCTAssertNotNil(content?.first?["text"], "应返回错误描述文本")
    }

    // MARK: - 12. 错误码与 String id 测试

    /// 验证 errorCode 映射：未知方法 = -32601，参数无效 = -32602
    func testErrorCodeValues() async throws {
        try await server.start()

        // 未知方法 → -32601 Method not found
        let unknownResponse = await sendRequestAndWait(method: "foo/bar", id: 24)
        let unknownError = unknownResponse?["error"] as? [String: Any]
        XCTAssertEqual(unknownError?["code"] as? Int, -32601, "未知方法应返回 -32601")

        // 参数无效 → -32602 Invalid params
        let invalidParamsResponse = await sendRequestAndWaitNoParams(method: "tools/call", id: 25)
        let invalidError = invalidParamsResponse?["error"] as? [String: Any]
        XCTAssertEqual(invalidError?["code"] as? Int, -32602, "参数无效应返回 -32602")
    }

    /// String 类型 id 应在响应中原样返回
    func testStringIDInResponse() async throws {
        try await server.start()

        transport.resetSentData()

        // 使用 String 类型 id
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "req-abc-123",
            "method": "ping"
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        transport.inject(data)

        // 等待响应
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let responseData = transport.sentData.last,
               let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                XCTAssertEqual(json["id"] as? String, "req-abc-123", "String id 应原样返回")
                return
            }
        }
        XCTFail("应在 2 秒内收到响应")
    }

    // MARK: - 辅助方法

    /// 发送 JSON-RPC 请求并等待响应。
    /// 通过 transport.inject 注入请求，轮询 transport.sentData 等待响应。
    /// - Parameters:
    ///   - method: JSON-RPC 方法名
    ///   - params: 请求参数（可选）
    ///   - id: 请求 id
    /// - Returns: 响应 JSON 字典（超时返回 nil）
    private func sendRequestAndWait(method: String, params: [String: Any]? = nil, id: Int) async -> [String: Any]? {
        transport.resetSentData()

        var request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if let params = params {
            request["params"] = params
        }

        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            return nil
        }

        transport.inject(requestData)

        // 轮询等待响应（最多 2 秒）
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if let responseData = transport.sentData.last,
               let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                return json
            }
        }
        return nil
    }

    /// 发送不带 params 字段的 JSON-RPC 请求并等待响应。
    /// - Parameters:
    ///   - method: JSON-RPC 方法名
    ///   - id: 请求 id
    /// - Returns: 响应 JSON 字典（超时返回 nil）
    private func sendRequestAndWaitNoParams(method: String, id: Int) async -> [String: Any]? {
        transport.resetSentData()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
            // 不包含 params 字段
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            return nil
        }

        transport.inject(requestData)

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let responseData = transport.sentData.last,
               let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                return json
            }
        }
        return nil
    }
}

// MARK: - ServerMockTransport（Server 端测试用 Mock 传输层）

/// 测试用 Server 端 Mock 传输层。
///
/// 与 MCPClientTests 中的 MockTransport 方向相反：
/// - MockTransport：接收 send() 请求 → 通过 messages() 返回响应（模拟 Server 响应客户端）
/// - ServerMockTransport：通过 inject() 注入请求 → 捕获 send() 响应（模拟客户端请求 Server）
///
/// 测试通过 `inject(_:)` 模拟外部客户端发送 JSON-RPC 请求，
/// 通过 `sentData` 断言 Server 返回的响应。
final class ServerMockTransport: @unchecked Sendable, MCPTransport {
    /// 消息流 continuation（测试通过 inject 注入请求数据）
    private var continuation: AsyncStream<Data>.Continuation?
    /// 已发送的响应数据列表（Server 通过 send() 返回的响应，测试断言用）
    private(set) var sentData: [Data] = []
    /// 线程安全锁
    private let lock = NSLock()
    /// 是否已连接
    private var isConnected = false

    func connect() async throws {
        lock.lock()
        isConnected = true
        lock.unlock()
    }

    func disconnect() async {
        lock.lock()
        isConnected = false
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    func send(_ data: Data) async throws {
        lock.lock()
        sentData.append(data)
        lock.unlock()
    }

    func messages() -> AsyncStream<Data> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    /// 测试辅助：向消息流注入请求数据（模拟外部客户端发送请求）
    /// - Parameter data: JSON-RPC 请求数据
    func inject(_ data: Data) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(data)
    }

    /// 测试辅助：清空已发送的响应数据
    func resetSentData() {
        lock.lock()
        sentData.removeAll()
        lock.unlock()
    }
}
