import Foundation
import AetherFoundation

/// 判断流式请求的错误是否由任务取消引发。取消属于正常控制流，不应作为网络错误上报给 UI。
func isRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}

/// 统一 SSE 流传输：空闲超时、HTTP 错误映射、取消传播与错误通知。
///
/// DeepSeek / Qwen / BFF 三个客户端只负责构造 URLRequest 与选择解析路径，
/// 网络层行为集中在此，避免各端超时、取消、错误处理漂移。
/// 解析统一走 Rust（`SSEParser`），同时支持 OpenAI 与 BFF 两种 SSE envelope。
public final class StreamTransport: @unchecked Sendable {
    /// 默认空闲超时：URLSession 在等待下一段数据时计时，收到数据即重置。
    public static let defaultTimeout: TimeInterval = 30

    private let session: URLSession
    private let timeout: TimeInterval
    /// HTTP 非 2xx 时把状态码 + 响应体映射为 LLMError（各供应商语义不同）。
    private let httpErrorMapper: @Sendable (HTTPURLResponse, String) -> LLMError
    /// 单实例对应单条流的解析状态（tool_calls 跨 chunk 累积）。
    private let parser = SSEParser()

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = StreamTransport.defaultTimeout,
        httpErrorMapper: @escaping @Sendable (HTTPURLResponse, String) -> LLMError = { http, body in
            LLMError.fromHTTPStatus(http.statusCode, body: body)
        }
    ) {
        self.session = session
        self.timeout = timeout
        self.httpErrorMapper = httpErrorMapper
    }

    /// 纯文本增量流。HTTP/网络错误已由传输层上报通知，此处只结束流。
    public func textStream(for request: URLRequest) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await line in self.lines(for: request) {
                        if let content = self.parser.parseChunk(from: line)?.choices?.first?.delta?.content {
                            continuation.yield(content)
                        }
                    }
                } catch {
                    // 错误已上报，流正常结束
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 带 tool_calls 累积的增量流。HTTP/网络错误已由传输层上报通知，此处只结束流。
    public func chunkStream(for request: URLRequest) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            let task = Task {
                var accumulated: [Int: AccumulatedToolCall] = [:]
                do {
                    for try await line in self.lines(for: request) {
                        if let parsed = self.parser.parseWithToolAccumulation(from: line, accumulated: &accumulated) {
                            continuation.yield(parsed)
                        }
                    }
                } catch {
                    // 错误已上报，流正常结束
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 发起请求并逐行产出 SSE 行。非 2xx / 网络错误先发出 `.llmErrorOccurred` 通知再抛出。
    /// 调用方停止迭代或所在 Task 取消时，底层 URLSession 请求随之取消。
    public func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = request
                    request.timeoutInterval = self.timeout
                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.networkError(NSLocalizedString("无效的 HTTP 响应", comment: ""))
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line + "\n"
                        }
                        throw self.httpErrorMapper(http, body)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    guard !isRequestCancellation(error), !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    let llmError = (error as? LLMError) ?? .networkError(error.localizedDescription)
                    await StreamTransport.report(llmError)
                    continuation.finish(throwing: llmError)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 在主线程发出错误通知（与既有 UI 监听约定一致）。
    static func report(_ error: LLMError) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .llmErrorOccurred,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
}

/// 构造 upstream 请求体与 URLRequest 的共享实现（三个客户端共用）。
extension ChatRequestBody {
    /// 序列化为上游 payload。images 存在时 content 改为 `[text, image_url]` 内容块数组，
    /// Codable 无法表达"字符串或数组"联合类型，故手动构造。
    /// - Parameter includeUsage: 是否附带 `stream_options.include_usage`（仅直连供应商支持）
    public func makeStreamPayload(includeUsage: Bool) -> Data? {
        var messagesPayload: [[String: Any]] = []
        for message in messages {
            var dict: [String: Any] = ["role": message.role]
            if let images = message.images, !images.isEmpty {
                var parts: [[String: Any]] = []
                if let text = message.content, !text.isEmpty {
                    parts.append(["type": "text", "text": text])
                }
                for base64 in images {
                    parts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(base64)"],
                    ])
                }
                dict["content"] = parts
            } else {
                dict["content"] = message.content ?? ""
            }
            if let toolCallId = message.tool_call_id {
                dict["tool_call_id"] = toolCallId
            }
            if let toolCalls = message.tool_calls {
                dict["tool_calls"] = toolCalls.map { toolCall in
                    [
                        "id": toolCall.id,
                        "type": toolCall.type,
                        "function": [
                            "name": toolCall.function.name,
                            "arguments": toolCall.function.arguments,
                        ],
                    ] as [String: Any]
                }
            }
            messagesPayload.append(dict)
        }

        var payload: [String: Any] = [
            "model": model,
            "messages": messagesPayload,
            "stream": stream,
        ]
        if let maxTokens = max_tokens { payload["max_tokens"] = maxTokens }
        if let temperature = temperature { payload["temperature"] = temperature }
        if let tools = tools {
            payload["tools"] = tools.map { tool in
                [
                    "type": tool.type,
                    "function": [
                        "name": tool.function.name,
                        "description": tool.function.description,
                        "parameters": tool.function.parameters.mapValues { $0.value },
                    ] as [String: Any],
                ] as [String: Any]
            }
        }
        if let toolChoice = tool_choice { payload["tool_choice"] = toolChoice }
        if includeUsage {
            payload["stream_options"] = ["include_usage": true]
        }
        return try? JSONSerialization.data(withJSONObject: payload, options: [])
    }

    /// 构造 POST 请求（JSON body + 调用方指定的鉴权头）。
    public func makeRequest(url: URL, headers: [String: String], includeUsage: Bool) -> URLRequest? {
        guard let body = makeStreamPayload(includeUsage: includeUsage) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body
        return request
    }
}
