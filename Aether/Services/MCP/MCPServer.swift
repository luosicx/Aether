import AetherFoundation
import Foundation
import os

// MARK: - MCP Server 实现（v1.1 Phase A: 反向暴露）
//
// 注意：本文件包含 MCPServer actor 主体与 ServerStdioTransport（Server 端 stdio 传输）。
// 与 MCPClient 方向相反：MCPClient 作为客户端向外部 Server 发请求，
// MCPServer 接收外部客户端的 JSON-RPC 请求并返回响应。
// JSON-RPC 2.0 格式与 MCPClient 一致，只是方向反了。

/// MCPServer 默认暴露的跨平台工具白名单（14 个）。
/// 排除 macOS 独有工具（AppleScript/Screenshot/OCR/Terminal/Window/App/File/Finder/Safari/SystemControl/InputAutomation），
/// 这些工具需要桌面环境且权限敏感，默认不对外暴露。
enum MCPServerDefaultTools {
    /// 跨平台工具名白名单（14 个）
    static let crossPlatform: [String] = [
        "create_alarm",
        "create_reminder",
        "get_current_time",
        "calculate",
        "get_location",
        "get_device_info",
        "read_clipboard",
        "write_clipboard",
        "open_url",
        "search_contacts",
        "get_weather",
        "run_shortcut",
        "list_shortcuts",
        "create_shortcut"
    ]
}

/// MCP Server，actor 隔离确保线程安全。
///
/// 接收外部 MCP 客户端（如 Claude Desktop）的 JSON-RPC 2.0 请求，
/// 将 Aether 的工具/资源/Prompts 反向暴露出去。
///
/// 处理方法：
/// - `initialize`：返回 server info（name: "aether", version: "1.1.0"）+ capabilities
/// - `tools/list`：从 `ToolRegistry.shared` 抽取工具定义，按白名单过滤
/// - `tools/call`：从 `ToolRegistry.shared` 执行工具，返回 content 数组
/// - `resources/list`：返回暴露的资源列表
/// - `prompts/list`：返回暴露的 Prompts 列表
///
/// 通过 `transport.send` 返回 JSON-RPC 响应。
actor MCPServer: MCPServerProtocol {
    /// 传输层（stdio / SSE / Mock）
    private let transport: MCPTransport
    /// 工具白名单（仅暴露白名单中的工具）
    private var toolWhitelist: [String]
    /// 暴露的资源列表
    private var resources: [MCPResource]
    /// 暴露的 Prompts 列表
    private var prompts: [MCPPrompt]
    /// 请求接收 Task
    private var receiveTask: Task<Void, Never>?
    /// 是否已启动
    private(set) var isRunning = false

    /// Server 信息（initialize 响应）
    private let serverInfo: [String: Any] = [
        "name": "aether",
        "version": "1.1.0"
    ]

    /// Server capabilities（initialize 响应）
    private let capabilities: [String: Any] = [
        "tools": ["listChanged": false],
        "resources": ["listChanged": false],
        "prompts": ["listChanged": false]
    ]

    /// 支持的协议版本
    private let protocolVersion = "2024-11-05"

    /// 构造 MCPServer
    /// - Parameters:
    ///   - transport: 传输层（stdio / SSE / Mock）
    ///   - toolWhitelist: 工具白名单（nil 时使用跨平台默认白名单 14 个）
    ///   - resources: 暴露的资源列表（缺省空）
    ///   - prompts: 暴露的 Prompts 列表（缺省空）
    init(
        transport: MCPTransport,
        toolWhitelist: [String]? = nil,
        resources: [MCPResource] = [],
        prompts: [MCPPrompt] = []
    ) {
        self.transport = transport
        self.toolWhitelist = toolWhitelist ?? MCPServerDefaultTools.crossPlatform
        self.resources = resources
        self.prompts = prompts
    }

    // MARK: - 生命周期管理

    /// 启动 Server：连接 transport，开始监听 JSON-RPC 请求。
    /// 重复启动为 no-op。
    func start() async throws {
        guard !isRunning else { return }

        // 先创建消息流（存储 continuation），避免请求到达时 continuation 未就绪
        let stream = transport.messages()

        // 启动请求接收 Task
        receiveTask = Task { [weak self] in
            for await data in stream {
                guard !Task.isCancelled else { return }
                await self?.handleRequestData(data)
            }
        }

        do {
            try await transport.connect()
            isRunning = true
            Logger.mcp.info("MCPServer 已启动，暴露 \(self.toolWhitelist.count) 个工具")
        } catch {
            receiveTask?.cancel()
            receiveTask = nil
            throw error
        }
    }

    /// 停止 Server：取消接收 Task、断开 transport。
    /// 重复停止为 no-op。
    func stop() async {
        guard isRunning else { return }
        receiveTask?.cancel()
        receiveTask = nil
        await transport.disconnect()
        isRunning = false
        Logger.mcp.info("MCPServer 已停止")
    }

    // MARK: - 注册接口

    /// 注册工具白名单（覆盖式）。
    /// - Parameter tools: 工具名数组（传空数组表示不暴露任何工具）
    func registerTools(_ tools: [String]) async {
        toolWhitelist = tools
        Logger.mcp.info("MCPServer 工具白名单已更新：\(tools.count) 个工具")
    }

    /// 注册暴露的资源列表（覆盖式）。
    /// - Parameter resources: 资源定义数组
    func registerResources(_ resources: [MCPResource]) async {
        self.resources = resources
        Logger.mcp.info("MCPServer 资源列表已更新：\(resources.count) 个资源")
    }

    /// 注册暴露的 Prompts 列表（覆盖式）。
    /// - Parameter prompts: Prompts 定义数组
    func registerPrompts(_ prompts: [MCPPrompt]) async {
        self.prompts = prompts
        Logger.mcp.info("MCPServer Prompts 列表已更新：\(prompts.count) 个 Prompts")
    }

    // MARK: - JSON-RPC 请求处理

    /// 处理接收到的请求数据：解析 JSON-RPC 2.0，按 method 分发，返回响应。
    private func handleRequestData(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else {
            // 非 JSON-RPC 请求，忽略
            return
        }

        // id 可能是 Int / String / Null（通知无 id）
        let id: Any? = json["id"]
        let params = json["params"] as? [String: Any]

        do {
            let result = try await dispatch(method: method, params: params)
            // 通知（无 id）不返回响应；有 id 时解包后传递，避免 Optional 被包装进 Any
            if let id = id {
                await sendResponse(id: id, result: result)
            }
        } catch {
            if let id = id {
                await sendErrorResponse(id: id, code: errorCode(for: error), message: error.localizedDescription)
            }
        }
    }

    /// 按 method 分发请求到对应处理方法。
    /// - Parameters:
    ///   - method: JSON-RPC 方法名
    ///   - params: 请求参数
    /// - Returns: result 字段内容
    private func dispatch(method: String, params: [String: Any]?) async throws -> [String: Any] {
        switch method {
        case "initialize":
            return [
                "protocolVersion": protocolVersion,
                "capabilities": capabilities,
                "serverInfo": serverInfo
            ]
        case "notifications/initialized":
            // 客户端初始化完成通知，无需响应（id 为 nil 时不会发送响应）
            return [:]
        case "tools/list":
            return try await handleToolsList()
        case "tools/call":
            return try await handleToolsCall(params: params)
        case "resources/list":
            return handleResourcesList()
        case "prompts/list":
            return handlePromptsList()
        case "ping":
            return [:]
        default:
            throw MCPError.protocolError("未知方法: \(method)")
        }
    }

    /// 处理 tools/list：从 ToolRegistry 抽取工具定义，按白名单过滤。
    /// - Returns: ["tools": [[String: Any]]]
    private func handleToolsList() async throws -> [String: Any] {
        // ToolRegistry.shared 是 @MainActor，需 await
        let whitelist = toolWhitelist
        let toolDefs: [ToolDefinition] = await MainActor.run {
            // 遍历白名单，从 ToolRegistry 取出对应工具的 definition
            ToolRegistry.shared.getToolNames().compactMap { name in
                guard whitelist.contains(name) else { return nil }
                return ToolRegistry.shared.getTool(named: name)?.definition
            }
        }

        let toolsArray: [[String: Any]] = toolDefs.map { def in
            [
                "name": def.name,
                "description": def.description,
                "inputSchema": def.parameters
            ]
        }
        return ["tools": toolsArray]
    }

    /// 处理 tools/call：执行指定工具，返回 content 数组。
    /// - Parameter params: ["name": 工具名, "arguments": 参数字典]
    /// - Returns: ["content": [["type": "text", "text": 结果]], "isError": Bool]
    private func handleToolsCall(params: [String: Any]?) async throws -> [String: Any] {
        guard let params = params,
              let toolName = params["name"] as? String else {
            throw MCPError.invalidResponse("tools/call 缺少 name 参数")
        }

        // 白名单校验
        guard toolWhitelist.contains(toolName) else {
            return [
                "content": [["type": "text", "text": "工具 \(toolName) 不在暴露白名单中"]],
                "isError": true
            ]
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]

        // ToolRegistry.shared 是 @MainActor，await 自动 hop 到 MainActor
        do {
            let result: String = try await ToolRegistry.shared.execute(name: toolName, arguments: arguments)
            return [
                "content": [["type": "text", "text": result]],
                "isError": false
            ]
        } catch {
            return [
                "content": [["type": "text", "text": "工具执行失败: \(error.localizedDescription)"]],
                "isError": true
            ]
        }
    }

    /// 处理 resources/list：返回暴露的资源列表。
    /// - Returns: ["resources": [[String: Any]]]
    private func handleResourcesList() -> [String: Any] {
        let resourcesArray: [[String: Any]] = resources.map { res in
            var dict: [String: Any] = [
                "uri": res.uri,
                "name": res.name
            ]
            if let desc = res.description { dict["description"] = desc }
            if let mime = res.mimeType { dict["mimeType"] = mime }
            return dict
        }
        return ["resources": resourcesArray]
    }

    /// 处理 prompts/list：返回暴露的 Prompts 列表。
    /// - Returns: ["prompts": [[String: Any]]]
    private func handlePromptsList() -> [String: Any] {
        let promptsArray: [[String: Any]] = prompts.map { prompt in
            var dict: [String: Any] = [
                "name": prompt.name,
                "description": prompt.description
            ]
            if let args = prompt.arguments {
                dict["arguments"] = args.map { arg in
                    var argDict: [String: Any] = [
                        "name": arg.name,
                        "required": arg.required
                    ]
                    if let desc = arg.description { argDict["description"] = desc }
                    return argDict
                }
            }
            return dict
        }
        return ["prompts": promptsArray]
    }

    // MARK: - JSON-RPC 响应发送

    /// 发送 JSON-RPC 成功响应。
    /// - Parameters:
    ///   - id: 请求 id（Int / String）
    ///   - result: result 字段内容
    private func sendResponse(id: Any, result: [String: Any]) async {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        await send(response)
    }

    /// 发送 JSON-RPC 错误响应。
    /// - Parameters:
    ///   - id: 请求 id
    ///   - code: JSON-RPC 错误码
    ///   - message: 错误信息
    private func sendErrorResponse(id: Any, code: Int, message: String) async {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        await send(response)
    }

    /// 序列化并发送 JSON-RPC 消息。
    /// - Parameter dict: 消息字典
    private func send(_ dict: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            Logger.mcp.error("MCPServer 响应序列化失败")
            return
        }
        do {
            try await transport.send(data)
        } catch {
            Logger.mcp.error("MCPServer 响应发送失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 将 MCPError 映射为 JSON-RPC 错误码。
    /// - Parameter error: 错误
    /// - Returns: JSON-RPC 错误码（-32603 内部错误 / -32601 方法不存在 / -32602 参数无效）
    private func errorCode(for error: Error) -> Int {
        if let mcpError = error as? MCPError {
            switch mcpError {
            case .protocolError:
                return -32601 // Method not found
            case .invalidResponse:
                return -32602 // Invalid params
            default:
                return -32603 // Internal error
            }
        }
        return -32603
    }
}

// MARK: - ServerStdioTransport（Server 端 stdio 传输）

/// Server 端 stdio 传输：读取当前进程的 stdin，写入 stdout。
///
/// 与 `StdioTransport`（客户端，启动子进程）方向相反：
/// `StdioTransport` 是 Aether 作为客户端去连接外部 MCP Server；
/// `ServerStdioTransport` 是 Aether 作为 Server 被外部客户端（如 Claude Desktop）通过 stdio 调用。
///
/// - Note: 仅在 Aether 以命令行模式启动时有效（GUI 模式下 stdin/stdout 通常未连接）。
///   生产环境中，Claude Desktop 会将 Aether 作为子进程启动并通过 stdin/stdout 通信。
final class ServerStdioTransport: @unchecked Sendable, MCPTransport {
    /// stdin 读取句柄
    private let inputHandle: FileHandle
    /// stdout 写入句柄
    private let outputHandle: FileHandle
    /// 消息流 continuation（由 messages() 设置）
    private var continuation: AsyncStream<Data>.Continuation?
    /// 行缓冲（readabilityHandler 可能返回不完整行，需按 \n 分割）
    private var lineBuffer = ""
    /// 线程安全锁（readabilityHandler 在后台队列回调）
    private let lock = NSLock()
    /// 是否已连接
    private var isConnected = false

    /// 构造 ServerStdioTransport。
    /// - Parameters:
    ///   - input: 输入句柄（缺省 standardInput）
    ///   - output: 输出句柄（缺省 standardOutput）
    init(input: FileHandle = .standardInput,
         output: FileHandle = .standardOutput) {
        self.inputHandle = input
        self.outputHandle = output
    }

    // MARK: - MCPTransport 实现

    /// 连接：设置 stdin readabilityHandler 开始读取。
    func connect() async throws {
        guard !isConnected else { return }
        inputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.processStdinData(data)
        }
        isConnected = true
    }

    /// 断开：清理 readabilityHandler 并结束消息流。
    func disconnect() async {
        inputHandle.readabilityHandler = nil
        isConnected = false
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    /// 写入 stdout（JSON-RPC 消息 + 换行符）。
    func send(_ data: Data) async throws {
        var message = data
        message.append(0x0A) // 追加换行符 \n
        do {
            try outputHandle.write(contentsOf: message)
        } catch {
            throw MCPError.transportErrorWithCause(
                message: "stdout 写入失败: \(error.localizedDescription)",
                underlying: error
            )
        }
    }

    /// 创建消息接收流，存储 continuation 供 readabilityHandler 回调时 yield。
    func messages() -> AsyncStream<Data> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    // MARK: - 私有方法

    /// 处理 stdin 数据：按换行符分割，逐行 yield 给消息流。
    private func processStdinData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        lineBuffer += string
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) {
                continuation?.yield(lineData)
            }
        }
        lock.unlock()
    }
}
