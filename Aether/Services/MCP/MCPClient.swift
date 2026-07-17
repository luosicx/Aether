import Foundation
import AetherFoundation
import os

// MARK: - MCP 错误类型

/// MCP 客户端错误，覆盖连接失败、超时、协议错误等场景。
enum MCPError: Error, LocalizedError {
    /// 连接失败（如子进程启动失败、SSE 连接失败）
    case connectionFailed(String)
    /// 请求超时（未在超时时间内收到响应）
    case timeout
    /// JSON-RPC 协议错误（如方法不存在、参数无效）
    case protocolError(String)
    /// 传输层错误（如写入失败、网络异常）
    case transportError(String)
    /// 未连接（尝试在未连接状态下发送请求）
    case notConnected
    /// 响应格式无效（如 JSON 解析失败、缺少必要字段）
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "MCP 连接失败: \(msg)"
        case .timeout:
            return "MCP 请求超时"
        case .protocolError(let msg):
            return "MCP 协议错误: \(msg)"
        case .transportError(let msg):
            return "MCP 传输错误: \(msg)"
        case .notConnected:
            return "MCP 客户端未连接"
        case .invalidResponse(let msg):
            return "MCP 响应无效: \(msg)"
        }
    }
}

// MARK: - MCP 传输层协议

/// MCP 传输层抽象，定义连接、断开、发送、接收四个核心能力。
/// 用于解耦 MCPClient 与具体传输实现（stdio / SSE），便于测试注入 Mock。
protocol MCPTransport: Sendable {
    /// 建立传输连接
    func connect() async throws
    /// 断开传输连接
    func disconnect() async
    /// 发送数据（一行 JSON-RPC 消息）
    func send(_ data: Data) async throws
    /// 获取消息接收流（每条消息一个 Data）
    func messages() -> AsyncStream<Data>
}

// MARK: - stdio 传输（仅 macOS，Process + Pipe）

#if os(macOS)
/// stdio 传输实现：通过 Process 启动子进程，经 stdin/stdout 通信。
/// 使用 readabilityHandler 异步读取 stdout，按换行符分割 JSON-RPC 消息。
final class StdioTransport: @unchecked Sendable, MCPTransport {
    /// 子进程
    private let process: Process
    /// stdin 管道（写入请求）
    private let stdinPipe: Pipe
    /// stdout 管道（读取响应）
    private let stdoutPipe: Pipe
    /// stderr 管道（捕获错误输出，不解析）
    private let stderrPipe: Pipe
    /// 消息流 continuation（由 messages() 设置）
    private var continuation: AsyncStream<Data>.Continuation?
    /// 行缓冲（readabilityHandler 可能返回不完整行，需按 \n 分割）
    private var lineBuffer = ""
    /// 线程安全锁（readabilityHandler 在后台队列回调）
    private let lock = NSLock()

    /// 构造 stdio 传输
    /// - Parameters:
    ///   - command: 可执行文件路径
    ///   - args: 启动参数
    ///   - env: 环境变量（nil 表示继承当前进程环境）
    init(command: String, args: [String], env: [String: String]?) {
        process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        if let env = env {
            process.environment = env
        }
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    // MARK: - MCPTransport 实现

    /// 启动子进程并设置 stdout readabilityHandler
    func connect() async throws {
        do {
            try process.run()
        } catch {
            throw MCPError.connectionFailed("子进程启动失败: \(error.localizedDescription)")
        }
        // 设置 readabilityHandler 异步读取 stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.processStdoutData(data)
        }
    }

    /// 终止子进程并清理 readabilityHandler
    func disconnect() async {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        continuation?.finish()
    }

    /// 写入 stdin（JSON-RPC 消息 + 换行符）
    func send(_ data: Data) async throws {
        var message = data
        message.append(0x0A) // 追加换行符 \n
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: message)
        } catch {
            throw MCPError.transportError("stdin 写入失败: \(error.localizedDescription)")
        }
    }

    /// 创建消息接收流，存储 continuation 供 readabilityHandler 回调时 yield
    func messages() -> AsyncStream<Data> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    // MARK: - 私有方法

    /// 处理 stdout 数据：按换行符分割，逐行 yield 给消息流
    private func processStdoutData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        lineBuffer += string
        // 按换行符分割完整行
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // 非空行解析为 JSON-RPC 消息
            if !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) {
                continuation?.yield(lineData)
            }
        }
        lock.unlock()
    }
}
#endif

// MARK: - SSE 传输（跨平台，URLSession）

/// SSE 传输实现：通过 URLSession 建立 SSE 连接，解析 endpoint 事件获取 POST URL。
///
/// MCP SSE 传输流程：
/// 1. 客户端 GET 请求 SSE 端点（Accept: text/event-stream）
/// 2. Server 发送 `endpoint` 事件，告知 POST 请求 URL
/// 3. 客户端 POST JSON-RPC 请求到该 URL
/// 4. Server 通过 SSE 流返回 JSON-RPC 响应
final class SSETransport: @unchecked Sendable, MCPTransport {
    private static let logger = Logger(subsystem: "com.aether.app", category: "MCPSecurity")

    /// SSE 端点 URL
    private let url: URL
    /// 自定义请求头（如 Authorization）
    private let headers: [String: String]?
    /// URLSession（默认 .shared，可注入用于测试）
    private let session: URLSession
    /// SSE 读取 Task
    private var readTask: Task<Void, Never>?
    /// 消息流 continuation
    private var continuation: AsyncStream<Data>.Continuation?
    /// POST 请求端点（由 endpoint 事件设置）
    private var postEndpoint: URL?
    /// 线程安全锁
    private let lock = NSLock()

    /// 构造 SSE 传输
    /// - Parameters:
    ///   - urlString: SSE 端点 URL 字符串
    ///   - headers: 自定义请求头
    ///   - session: URLSession（默认 .shared）
    init(urlString: String, headers: [String: String]?, session: URLSession = .shared) {
        self.url = URL(string: urlString) ?? URL(fileURLWithPath: "")
        self.headers = headers
        self.session = session
    }

    // MARK: - MCPTransport 实现

    /// 建立 SSE 连接，启动事件读取
    func connect() async throws {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw MCPError.connectionFailed("SSE 连接失败: HTTP \(code)")
            }

            // 启动 SSE 事件读取 Task（Task<Void, Never> 要求闭包非 throwing，故用 do/catch 包裹 for try await）
            readTask = Task { [weak self] in
                var event = ""
                var data = ""
                do {
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { return }
                        // 空行 = 事件边界
                        if line.isEmpty {
                            if !data.isEmpty {
                                self?.handleSSEEvent(event: event, data: data)
                            }
                            event = ""
                            data = ""
                        } else if line.hasPrefix("event: ") {
                            event = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            data = String(line.dropFirst(6))
                        }
                    }
                } catch {
                    // SSE 读取错误（如网络断开），结束消息流
                    self?.continuation?.finish()
                    return
                }
                // SSE 流正常结束
                self?.continuation?.finish()
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.connectionFailed("SSE 连接异常: \(error.localizedDescription)")
        }
    }

    /// 断开 SSE 连接
    func disconnect() async {
        readTask?.cancel()
        readTask = nil
        continuation?.finish()
    }

    /// POST 发送 JSON-RPC 请求到 postEndpoint
    func send(_ data: Data) async throws {
        guard let endpoint = postEndpoint else {
            throw MCPError.connectionFailed("SSE POST 端点未就绪")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        request.httpBody = data

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw MCPError.transportError("SSE POST 失败: HTTP \(http.statusCode)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.transportError("SSE POST 异常: \(error.localizedDescription)")
        }
    }

    /// 创建消息接收流
    func messages() -> AsyncStream<Data> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    // MARK: - 私有方法

    /// 处理 SSE 事件
    /// - endpoint 事件：设置 POST 端点 URL（校验与 SSE 连接同源，防劫持）
    /// - message 事件：yield JSON-RPC 响应到消息流
    private func handleSSEEvent(event: String, data: String) {
        switch event {
        case "endpoint":
            // endpoint URL 可能是相对路径，基于 SSE URL 解析
            guard let url = URL(string: data, relativeTo: self.url) else { return }
            // 安全校验：endpoint 必须与 SSE 连接同源（scheme + host + port），
            // 防止恶意 MCP Server 将后续请求（含 Authorization 头）劫持到攻击者服务器
            guard let sseScheme = self.url.scheme,
                  let sseHost = self.url.host,
                  let endpointScheme = url.scheme,
                  let endpointHost = url.host,
                  endpointScheme.lowercased() == sseScheme.lowercased(),
                  endpointHost.lowercased() == sseHost.lowercased(),
                  (url.port ?? self.url.port) == (self.url.port ?? url.port) else {
                // 拒绝跨域 endpoint，记录安全告警日志
                Self.logger.warning("检测到 MCP endpoint 劫持尝试：SSE=\(self.url.absoluteString, privacy: .public), endpoint=\(data, privacy: .public)")
                return
            }
            lock.lock()
            postEndpoint = url
            lock.unlock()
        case "message":
            // JSON-RPC 响应
            if let data = data.data(using: .utf8) {
                continuation?.yield(data)
            }
        default:
            break
        }
    }
}

// MARK: - MCP 客户端协议（用于 MCPClientManager 测试注入）

/// MCP 客户端契约，抽象连接与 MCP 方法调用。
/// MCPClient actor 遵循此协议，测试可注入 Mock 实现。
protocol MCPClientProtocol {
    /// 关联的配置
    var config: MCPConfig { get }
    /// 连接并完成 MCP 握手
    func connect() async throws
    /// 断开连接
    func disconnect() async
    /// 列出工具
    func listTools() async throws -> [MCPTool]
    /// 列出资源
    func listResources() async throws -> [MCPResource]
    /// 列出提示模板
    func listPrompts() async throws -> [MCPPrompt]
    /// 调用工具
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult
    /// 读取资源
    func readResource(uri: String) async throws -> [MCPResourceContent]
    /// 获取提示模板内容
    func getPrompt(name: String, arguments: [String: Any]) async throws -> MCPPromptResult
}

// MARK: - MCP 客户端实现

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
