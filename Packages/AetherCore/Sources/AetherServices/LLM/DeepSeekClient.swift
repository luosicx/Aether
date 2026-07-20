import Foundation
import AetherFoundation

/// DeepSeek API 客户端，实现 LLMProvider 协议，提供 chat 流式对话和 embed 向量嵌入两个核心能力。
/// nonisolated 设计允许跨 actor 调用。
///
/// P1-8: 原实现 `private lazy var session: URLSession = .shared` 在 nonisolated + @unchecked Sendable 类中
/// 跨 actor 首次访问存在数据竞争。URLSession.shared 是线程安全的全局常量，无需 lazy 延迟初始化，
/// 改为 `let` 后由编译器保证线程安全。
nonisolated public final class DeepSeekClient: LLMProvider, @unchecked Sendable {
    /// URLSession 实例（URLSession.shared 线程安全，无需 lazy）
    private let session: URLSession = .shared
    /// SSE 流解析器
    private let parser = SSEParser()

    /// 无参构造器，供 ModelProviderFactory 调用
    public init() {}

    /// 纯文本 chat 流，返回 AsyncStream<String>，逐 chunk yield 文本内容
    public func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                await self.streamChat(messages: messages, config: config, apiKey: apiKey, continuation: continuation)
            }
        }
    }

    /// 带工具调用 chat 流，返回 AsyncStream<ParsedChunk>，yield 含 content 和累积后的 toolCalls
    public func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            Task {
                await self.streamChatWithTools(messages: messages, config: config, tools: tools, apiKey: apiKey, continuation: continuation)
            }
        }
    }

    /// 批量文本嵌入。空入参短路返回空数组。HTTP 非 2xx 抛 LLMError 并发 .llmErrorOccurred 通知。
    /// 返回按 index 排序的向量数组。
    public func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let body: [String: Any] = [
            "model": APIConfig.embeddingModel,
            "input": texts
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: APIConfig.deepseekBaseURL + APIConfig.embeddingEndpoint) else {
            throw LLMError.unknown(NSLocalizedString("无效的 embedding 请求", comment: ""))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let rawBody = String(data: data, encoding: .utf8) ?? ""
                let err = LLMError.fromHTTPStatus(http.statusCode, body: rawBody)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .llmErrorOccurred,
                        object: nil,
                        userInfo: ["error": err]
                    )
                }
                throw err
            }
            let decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
            return decoded.data.sorted { $0.index < $1.index }.map(\.embedding)
        } catch let err as LLMError {
            throw err
        } catch {
            let llmErr = LLMError.networkError(error.localizedDescription)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .llmErrorOccurred,
                    object: nil,
                    userInfo: ["error": llmErr]
                )
            }
            throw llmErr
        }
    }

    /// 构造纯文本请求体，转交 sendRequest
    private func streamChat(messages: [APIMessage], config: ChatConfig, apiKey: String, continuation: AsyncStream<String>.Continuation) async {
        let body = ChatRequestBody(
            model: config.model,
            messages: messages.map {
                ChatRequestBody.ChatMessageBody(
                    role: $0.role,
                    content: $0.content,
                    images: $0.images,
                    tool_call_id: $0.toolCallId,
                    tool_calls: $0.toolCalls?.map {
                        ChatRequestBody.ToolCallBody(
                            id: $0.id,
                            type: $0.type,
                            function: ChatRequestBody.FunctionBody(
                                name: $0.function.name,
                                arguments: $0.function.arguments
                            )
                        )
                    }
                )
            },
            stream: true,
            max_tokens: config.maxTokens,
            temperature: config.temperature,
            tools: nil,
            tool_choice: nil
        )
        await sendRequest(body: body, apiKey: apiKey, continuation: continuation)
    }

    /// 构造带工具的请求体，转交 sendRequestWithTools
    private func streamChatWithTools(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String, continuation: AsyncStream<ParsedChunk>.Continuation) async {
        let body = ChatRequestBody(
            model: config.model,
            messages: messages.map {
                ChatRequestBody.ChatMessageBody(
                    role: $0.role,
                    content: $0.content,
                    images: $0.images,
                    tool_call_id: $0.toolCallId,
                    tool_calls: $0.toolCalls?.map {
                        ChatRequestBody.ToolCallBody(
                            id: $0.id,
                            type: $0.type,
                            function: ChatRequestBody.FunctionBody(
                                name: $0.function.name,
                                arguments: $0.function.arguments
                            )
                        )
                    }
                )
            },
            stream: true,
            max_tokens: config.maxTokens,
            temperature: config.temperature,
            tools: tools,
            tool_choice: "auto"
        )
        await sendRequestWithTools(body: body, apiKey: apiKey, continuation: continuation)
    }

    /// 发送纯文本 chat 请求并流式解析 SSE。HTTP 错误发通知并 finish。
    /// 逐行解析 `data: ` 前缀，跳过 [DONE]，yield content。
    private func sendRequest(body: ChatRequestBody, apiKey: String, continuation: AsyncStream<String>.Continuation) async {
        guard let url = URL(string: APIConfig.deepseekBaseURL + APIConfig.chatEndpoint) else {
            continuation.finish()
            return
        }
        // Day 5 补充A：手动构建请求体，支持多模态 content（图片以 image_url 形式嵌入 content 数组）
        // 为何手动构造 payload 而非用 JSONEncoder：images 存在时 content 需改为数组结构 [text, image_url]，
        // Codable 无法表达这种"字符串或数组"的联合类型，故手动构造 [String: Any] 字典
        var messagesPayload: [[String: Any]] = []
        for msg in body.messages {
            var msgDict: [String: Any] = ["role": msg.role]
            if let images = msg.images, !images.isEmpty {
                // 多模态：content 改为内容块数组（text + image_url）
                var contentParts: [[String: Any]] = []
                if let text = msg.content, !text.isEmpty {
                    contentParts.append(["type": "text", "text": text])
                }
                for base64String in images {
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]
                    ])
                }
                msgDict["content"] = contentParts
            } else {
                // 无图片：保持原有字符串 content 路径
                msgDict["content"] = msg.content ?? ""
            }
            if let toolCallId = msg.tool_call_id {
                msgDict["tool_call_id"] = toolCallId
            }
            if let toolCalls = msg.tool_calls {
                msgDict["tool_calls"] = toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": tc.type,
                        "function": [
                            "name": tc.function.name,
                            "arguments": tc.function.arguments
                        ]
                    ] as [String: Any]
                }
            }
            messagesPayload.append(msgDict)
        }
        var payload: [String: Any] = [
            "model": body.model,
            "messages": messagesPayload,
            "stream": body.stream
        ]
        if let maxTokens = body.max_tokens { payload["max_tokens"] = maxTokens }
        if let temperature = body.temperature { payload["temperature"] = temperature }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            continuation.finish()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line
                }
                let err = LLMError.fromHTTPStatus(http.statusCode, body: errorBody)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .llmErrorOccurred,
                        object: nil,
                        userInfo: ["error": err]
                    )
                }
                continuation.finish()
                return
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }
                guard let data = jsonStr.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data),
                      let content = chunk.choices?.first?.delta?.content else { continue }
                continuation.yield(content)
            }
        } catch {
            let err = LLMError.networkError(error.localizedDescription)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .llmErrorOccurred,
                    object: nil,
                    userInfo: ["error": err]
                )
            }
        }
        continuation.finish()
    }

    /// 发送带工具的 chat 请求并流式解析 SSE。用 SSEParser.parseWithToolAccumulation 累积 tool_calls。
    private func sendRequestWithTools(body: ChatRequestBody, apiKey: String, continuation: AsyncStream<ParsedChunk>.Continuation) async {
        // 为何用 JSONEncoder 而非手动构造：工具路径无多模态 content（不走 images 分支），
        // Codable 自动序列化更安全；AnyCodable 处理 tool_calls parameters 的动态类型
        guard let url = URL(string: APIConfig.deepseekBaseURL + APIConfig.chatEndpoint),
              let jsonData = try? JSONEncoder().encode(body) else {
            continuation.finish()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line
                }
                let err = LLMError.fromHTTPStatus(http.statusCode, body: errorBody)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .llmErrorOccurred,
                        object: nil,
                        userInfo: ["error": err]
                    )
                }
                continuation.finish()
                return
            }
            var toolAccum: [Int: AccumulatedToolCall] = [:]
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }
                if let parsed = parser.parseWithToolAccumulation(from: line, accumulated: &toolAccum) {
                    continuation.yield(parsed)
                }
            }
        } catch {
            let err = LLMError.networkError(error.localizedDescription)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .llmErrorOccurred,
                    object: nil,
                    userInfo: ["error": err]
                )
            }
        }
        continuation.finish()
    }
}

/// LLM 错误通知名，userInfo["error"] 为 LLMError 实例
public extension Notification.Name {
    static let llmErrorOccurred = Notification.Name("llmErrorOccurred")
}
