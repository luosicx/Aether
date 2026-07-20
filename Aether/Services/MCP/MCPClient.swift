import AetherFoundation
import Foundation

// MARK: - MCP 客户端实现
//
// 注意：本文件仅包含 MCPClient actor 主体。错误类型（MCPError）、传输层协议
// （MCPTransport）与实现（StdioTransport / SSETransport）、客户端协议（MCPClientProtocol）
// 已拆分到独立文件，便于维护与测试。

/// MCP 客户端，actor 隔离确保线程安全。
///
/// 支持 JSON-RPC 2.0 协议，通过 stdio（macOS）或 SSE（跨平台）传输。
/// 内部使用 request id 匹配请求/响应，支持超时取消。
actor MCPClient: MCPClientProtocol {
    /// 关联的配置
    let config: MCPConfig
    /// 传输层（stdio / SSE / Mock）
    private let transport: MCPTransport
    /// 下一个 JSON-RPC 请求 id（自增）
    private var nextID: Int = 0
    /// 待响应的请求映射（id -> continuation）
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    /// 响应接收 Task
    private var receiveTask: Task<Void, Never>?
    /// 是否已连接
    private(set) var isConnected = false
    /// 请求超时时间（秒）
    private let requestTimeout: TimeInterval = 30

    /// 构造 MCP 客户端
    /// - Parameters:
    ///   - config: MCP Server 配置
    ///   - transport: 传输层（nil 时按 config.transport 自动创建）
    /// - Throws: 自动创建传输层时可能抛出 MCPError（如 iOS 平台遇到 stdio 传输）
    init(config: MCPConfig, transport: MCPTransport? = nil) throws {
        self.config = config
        if let transport = transport {
            self.transport = transport
        } else {
            self.transport = try MCPClient.makeTransport(for: config)
        }
    }

    // MARK: - 连接管理

    /// 连接到 MCP Server，完成 initialize 握手。
    /// 流程：创建消息流 → 启动接收 → 连接传输层 → initialize → 发送 initialized 通知
    func connect() async throws {
        guard !isConnected else { return }

        // 先创建消息流（存储 continuation），避免响应到达时 continuation 未就绪
        let stream = transport.messages()

        // 启动响应接收 Task
        receiveTask = Task { [weak self] in
            for await data in stream {
                guard !Task.isCancelled else { return }
                await self?.handleResponseData(data)
            }
        }

        do {
            // 连接传输层
            try await transport.connect()

            // MCP initialize 握手
            _ = try await initialize()

            // 发送 initialized 通知（无需响应）
            try await sendNotification(method: "notifications/initialized")

            isConnected = true
        } catch {
            // 连接失败：清理接收 Task 和 pending 请求
            receiveTask?.cancel()
            receiveTask = nil
            failAllPendingRequests(with: error)
            throw error
        }
    }

    /// 断开连接：取消接收 Task、断开传输层、取消所有 pending 请求
    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        await transport.disconnect()
        failAllPendingRequests(with: MCPError.connectionFailed("连接已断开"))
        isConnected = false
    }

    // MARK: - MCP 方法

    /// MCP initialize 握手：发送协议版本与客户端信息
    private func initialize() async throws -> [String: Any] {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "Aether", "version": "1.0"]
        ]
        return try await sendRequest(method: "initialize", params: params)
    }

    /// tools/list：获取 Server 暴露的工具列表
    func listTools() async throws -> [MCPTool] {
        let response = try await sendRequest(method: "tools/list", params: nil)
        guard let result = response["result"] as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }
        return toolsArray.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let description = dict["description"] as? String else {
                return nil
            }
            let inputSchema = dict["inputSchema"] as? [String: Any] ?? [:]
            return MCPTool(name: name, description: description, inputSchema: inputSchema)
        }
    }

    /// resources/list：获取 Server 暴露的资源列表
    func listResources() async throws -> [MCPResource] {
        let response = try await sendRequest(method: "resources/list", params: nil)
        guard let result = response["result"] as? [String: Any],
              let resourcesArray = result["resources"] as? [[String: Any]] else {
            return []
        }
        return resourcesArray.compactMap { dict in
            guard let uri = dict["uri"] as? String,
                  let name = dict["name"] as? String else {
                return nil
            }
            return MCPResource(
                uri: uri,
                name: name,
                description: dict["description"] as? String,
                mimeType: dict["mimeType"] as? String
            )
        }
    }

    /// prompts/list：获取 Server 暴露的提示模板列表
    func listPrompts() async throws -> [MCPPrompt] {
        let response = try await sendRequest(method: "prompts/list", params: nil)
        guard let result = response["result"] as? [String: Any],
              let promptsArray = result["prompts"] as? [[String: Any]] else {
            return []
        }
        return promptsArray.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let description = dict["description"] as? String else {
                return nil
            }
            let arguments = (dict["arguments"] as? [[String: Any]])?.compactMap { argDict -> MCPPromptArgument? in
                guard let argName = argDict["name"] as? String else { return nil }
                return MCPPromptArgument(
                    name: argName,
                    description: argDict["description"] as? String,
                    required: argDict["required"] as? Bool ?? false
                )
            }
            return MCPPrompt(name: name, description: description, arguments: arguments)
        }
    }

    /// tools/call：调用指定工具
    /// - Parameters:
    ///   - name: 工具名
    ///   - arguments: 工具参数
    /// - Returns: 工具调用结果（content + isError）
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]
        let response = try await sendRequest(method: "tools/call", params: params)
        guard let result = response["result"] as? [String: Any] else {
            throw MCPError.invalidResponse("tools/call 响应缺少 result")
        }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(MCPToolCallResult.self, from: resultData)
    }

    /// resources/read：读取指定资源
    /// - Parameter uri: 资源 URI
    /// - Returns: 资源内容列表
    func readResource(uri: String) async throws -> [MCPResourceContent] {
        let params: [String: Any] = ["uri": uri]
        let response = try await sendRequest(method: "resources/read", params: params)
        guard let result = response["result"] as? [String: Any],
              let contentsArray = result["contents"] as? [[String: Any]] else {
            return []
        }
        let dataArray = try JSONSerialization.data(withJSONObject: contentsArray)
        return try JSONDecoder().decode([MCPResourceContent].self, from: dataArray)
    }

    /// prompts/get：获取指定提示模板内容
    /// - Parameters:
    ///   - name: 提示模板名
    ///   - arguments: 参数
    /// - Returns: 提示模板结果（description + messages）
    func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult {
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]
        let response = try await sendRequest(method: "prompts/get", params: params)
        guard let result = response["result"] as? [String: Any] else {
            throw MCPError.invalidResponse("prompts/get 响应缺少 result")
        }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(MCPPromptResult.self, from: resultData)
    }

    // MARK: - JSON-RPC 请求/响应处理

    /// 发送 JSON-RPC 请求并等待响应。
    /// 使用 withCheckedThrowingContinuation 挂起，由 handleResponseData 或超时 Task 恢复。
    /// - Parameters:
    ///   - method: JSON-RPC 方法名
    ///   - params: 请求参数（nil 时使用空对象）
    /// - Returns: 完整 JSON-RPC 响应字典（含 jsonrpc / id / result）
    private func sendRequest(method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard isConnected || method == "initialize" else {
            throw MCPError.notConnected
        }

        let id = nextID
        nextID += 1

        // 构造 JSON-RPC 2.0 请求
        var request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if let params = params {
            request["params"] = params
        }
        let requestData = try JSONSerialization.data(withJSONObject: request)

        // 捕获到局部变量，避免 Task 闭包访问 actor 属性
        let transport = self.transport
        let timeout = self.requestTimeout

        let responseData: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            // 先注册 continuation，再发送请求，避免响应先到导致丢失
            pendingRequests[id] = continuation

            // 超时 Task：超时后恢复 continuation 并抛出 timeout
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.handleTimeout(id: id)
            }

            // 发送 Task：异步发送请求，失败时恢复 continuation
            Task { [weak self] in
                do {
                    try await transport.send(requestData)
                } catch {
                    await self?.failRequest(id: id, error: error)
                }
            }
        }

        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw MCPError.invalidResponse("无法解析 JSON 响应")
        }

        // 检查 JSON-RPC error 字段
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            let code = error["code"] as? Int ?? -1
            throw MCPError.protocolError("[\(code)] \(message)")
        }

        return json
    }

    /// 发送 JSON-RPC 通知（无 id，不期待响应）
    /// - Parameters:
    ///   - method: 方法名
    ///   - params: 参数（可选）
    private func sendNotification(method: String, params: [String: Any]? = nil) async throws {
        var notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params = params {
            notification["params"] = params
        }
        let data = try JSONSerialization.data(withJSONObject: notification)
        try await transport.send(data)
    }

    /// 处理接收到的响应数据：按 id 匹配 pending 请求并恢复 continuation
    private func handleResponseData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int else {
            // 非 JSON-RPC 响应或无 id（通知），忽略
            return
        }
        guard let continuation = pendingRequests.removeValue(forKey: id) else {
            // 无匹配的 pending 请求（可能已超时），忽略
            return
        }
        continuation.resume(returning: data)
    }

    /// 处理请求超时：移除 pending 请求并抛出 timeout
    private func handleTimeout(id: Int) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: MCPError.timeout)
        }
    }

    /// 处理发送失败：移除 pending 请求并抛出错误
    private func failRequest(id: Int, error: Error) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    /// 取消所有 pending 请求（断开连接时调用）
    private func failAllPendingRequests(with error: Error) {
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: error)
        }
        pendingRequests.removeAll()
    }

    // MARK: - 传输层工厂

    /// 按 config.transport 创建对应的传输层实例
    /// - Throws: iOS 平台遇到 stdio 传输时抛 MCPError.connectionFailed（防止 JSON 持久化恢复时崩溃）
    private static func makeTransport(for config: MCPConfig) throws -> MCPTransport {
        switch config.transport {
        case .stdio(let command, let args, let env):
            #if os(macOS)
            return StdioTransport(command: command, args: args, env: env)
            #else
            // iOS 不支持 Process，stdio 传输不可用，抛错而非 fatalError
            // 防止配置通过 JSON 持久化恢复时在 iOS 上触发崩溃
            throw MCPError.connectionFailed("stdio 传输仅在 macOS 上可用，iOS 请使用 SSE 传输")
            #endif
        case .sse(let url, let headers):
            return SSETransport(urlString: url, headers: headers)
        }
    }
}
