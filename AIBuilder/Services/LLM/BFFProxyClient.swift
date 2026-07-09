import Foundation

/// Day 15: BFF 代理客户端，实现 LLMProvider 协议。
/// 将设备端请求转发到 BFF 网关（Cloudflare Workers），由服务端持有上游 API Key，
/// 设备仅携带 X-BFF-Token 鉴权。请求体结构与 DeepSeekClient 一致，SSE 解析复用 SSEParser。
/// nonisolated 设计允许跨 actor 调用。
nonisolated final class BFFProxyClient: LLMProvider {
    /// 路由目标上游供应商（写入 X-Provider Header，服务端据此选择上游 key/endpoint）
    private let provider: ModelProvider
    /// BFF 配置（endpoint / token / 限流参数）
    private let config: BFFConfig
    /// URLSession（默认 .shared，可注入用于测试）
    private let session: URLSession
    /// SSE 流解析器
    private let parser = SSEParser()

    /// 构造 BFF 代理客户端
    /// - Parameters:
    ///   - provider: 路由目标供应商
    ///   - config: BFF 配置
    ///   - session: URLSession（默认 .shared）
    init(provider: ModelProvider, config: BFFConfig, session: URLSession = .shared) {
        self.provider = provider
        self.config = config
        self.session = session
    }

    /// 纯文本 chat 流，返回 AsyncStream<String>，逐 chunk yield 文本内容
    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                await self.streamChat(messages: messages, config: config, apiKey: apiKey, continuation: continuation)
            }
        }
    }

    /// 带工具调用 chat 流，返回 AsyncStream<ParsedChunk>，yield 含 content 和累积后的 toolCalls
    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            Task {
                await self.streamChatWithTools(messages: messages, config: config, tools: tools, apiKey: apiKey, continuation: continuation)
            }
        }
    }

    /// 批量文本嵌入。空入参短路返回空数组。HTTP 非 2xx 抛 LLMError 并发 .llmErrorOccurred 通知。
    /// 返回按 index 排序的向量数组。
    /// 注意：BFF 模式下 apiKey 参数不使用（服务端持有上游 key）。
    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        // BFF 模式下 apiKey 不使用（服务端持有上游 key）
        let body: [String: Any] = [
            "model": provider.defaultEmbeddingModel,
            "input": texts
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: config.endpointURL.appending(path: "v1/embeddings").absoluteString) else {
            throw LLMError.unknown(NSLocalizedString("无效的 BFF embedding 请求", comment: ""))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.config.userToken, forHTTPHeaderField: "X-BFF-Token")
        request.setValue(self.provider.rawValue, forHTTPHeaderField: "X-Provider")
        request.httpBody = jsonData
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let err = await bffError(from: http)
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
                ChatRequestBody.ChatMessageBody(role: $0.role, content: $0.content, images: $0.images, tool_call_id: $0.toolCallId, tool_calls: $0.toolCalls?.map { ChatRequestBody.ToolCallBody(id: $0.id, type: $0.type, function: ChatRequestBody.FunctionBody(name: $0.function.name, arguments: $0.function.arguments)) })
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
                ChatRequestBody.ChatMessageBody(role: $0.role, content: $0.content, images: $0.images, tool_call_id: $0.toolCallId, tool_calls: $0.toolCalls?.map { ChatRequestBody.ToolCallBody(id: $0.id, type: $0.type, function: ChatRequestBody.FunctionBody(name: $0.function.name, arguments: $0.function.arguments)) })
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
        // BFF 模式下 apiKey 不使用（服务端持有上游 key）
        guard let url = URL(string: config.endpointURL.appending(path: "v1/chat/completions").absoluteString) else {
            continuation.finish()
            return
        }
        // 手动构建请求体，支持多模态 content（图片以 image_url 形式嵌入 content 数组）
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
        request.setValue(self.config.userToken, forHTTPHeaderField: "X-BFF-Token")
        request.setValue(self.provider.rawValue, forHTTPHeaderField: "X-Provider")
        request.httpBody = jsonData
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // 消费错误响应体（避免连接泄漏）
                for try await _ in bytes.lines { }
                _ = await bffError(from: http)
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
        // BFF 模式下 apiKey 不使用（服务端持有上游 key）
        guard let url = URL(string: config.endpointURL.appending(path: "v1/chat/completions").absoluteString),
              let jsonData = try? JSONEncoder().encode(body) else {
            continuation.finish()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.config.userToken, forHTTPHeaderField: "X-BFF-Token")
        request.setValue(self.provider.rawValue, forHTTPHeaderField: "X-Provider")
        request.httpBody = jsonData
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // 消费错误响应体（避免连接泄漏）
                for try await _ in bytes.lines { }
                _ = await bffError(from: http)
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

    /// 根据 HTTP 状态码构造 BFF 错误并发 .llmErrorOccurred 通知。
    /// - 401 → BFF Token 无效
    /// - 429 → 解析 Retry-After Header → rateLimited
    /// - 5xx → BFF 服务异常
    /// - 其他 → apiError
    /// - Parameter http: HTTP 响应
    /// - Returns: 构造的 LLMError
    private func bffError(from http: HTTPURLResponse) async -> LLMError {
        let err: LLMError
        switch http.statusCode {
        case 401:
            err = .llmErrorOccurred(NSLocalizedString("BFF Token 无效", comment: ""))
        case 429:
            // 解析 Retry-After Header（秒），缺省 60
            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            err = .rateLimited(retryAfter: max(retryAfter, 1))
        case 500...599:
            err = .llmErrorOccurred(NSLocalizedString("BFF 服务异常", comment: ""))
        default:
            err = .apiError(code: http.statusCode, message: "BFF HTTP \(http.statusCode)")
        }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .llmErrorOccurred,
                object: nil,
                userInfo: ["error": err]
            )
        }
        return err
    }
}
