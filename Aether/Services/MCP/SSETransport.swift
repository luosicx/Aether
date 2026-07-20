import Foundation
import os

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
            // Task 引用通过 setReadTask(_:) 持锁赋值，与 disconnect() 串行化
            let task = Task { [weak self] in
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
                    self?.finishContinuation()
                    return
                }
                // SSE 流正常结束
                self?.finishContinuation()
            }
            setReadTask(task)
        } catch let error as MCPError {
            throw error
        } catch {
            // P2-3: 携带 underlying 保留原始 Error 上下文
            throw MCPError.connectionFailedWithCause(message: "SSE 连接异常: \(error.localizedDescription)", underlying: error)
        }
    }

    /// 断开 SSE 连接
    func disconnect() async {
        // 持锁清理 readTask 与 continuation，与 connect() / messages() / send() 串行化
        lock.lock()
        readTask?.cancel()
        readTask = nil
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    /// POST 发送 JSON-RPC 请求到 postEndpoint
    func send(_ data: Data) async throws {
        // 持锁读取 postEndpoint 快照，避免与 handleSSEEvent() 写入竞争
        lock.lock()
        let endpoint = postEndpoint
        lock.unlock()
        guard let endpoint = endpoint else {
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
            // P2-3: 携带 underlying 保留原始 Error 上下文
            throw MCPError.transportErrorWithCause(message: "SSE POST 异常: \(error.localizedDescription)", underlying: error)
        }
    }

    /// 创建消息接收流
    /// - Note: 持锁设置 continuation，与 disconnect() / handleSSEEvent() 串行化
    func messages() -> AsyncStream<Data> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    // MARK: - 私有方法（锁内访问的辅助方法）

    /// 持锁设置 readTask（同时取消旧 task）
    private func setReadTask(_ task: Task<Void, Never>) {
        lock.lock()
        readTask?.cancel()
        readTask = task
        lock.unlock()
    }

    /// 持锁结束 continuation（防 disconnect() 后重复 finish）
    private func finishContinuation() {
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

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
            // JSON-RPC 响应（持锁 yield，避免与 disconnect() 后 finish 重复访问）
            if let data = data.data(using: .utf8) {
                lock.lock()
                continuation?.yield(data)
                lock.unlock()
            }
        default:
            break
        }
    }
}
