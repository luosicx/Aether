import Foundation
import AetherFoundation

/// DeepSeek API 客户端，实现 LLMProvider 协议，提供 chat 流式对话和 embed 向量嵌入两个核心能力。
/// nonisolated 设计允许跨 actor 调用。网络层行为（超时/取消/错误通知）统一由 StreamTransport 承担。
nonisolated public final class DeepSeekClient: LLMProvider, @unchecked Sendable {
    /// URLSession 实例（URLSession.shared 线程安全，无需 lazy）
    private let session: URLSession = .shared
    /// 统一 SSE 传输层
    private let transport: StreamTransport

    /// 无参构造器，供 ModelProviderFactory 调用
    public init() {
        transport = StreamTransport(session: session)
    }

    /// 纯文本 chat 流，返回 AsyncStream<String>，逐 chunk yield 文本内容
    public func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        guard let request = makeRequest(messages: messages, config: config, tools: nil, apiKey: apiKey) else {
            return AsyncStream { $0.finish() }
        }
        return transport.textStream(for: request)
    }

    /// 带工具调用 chat 流，返回 AsyncStream<ParsedChunk>，yield 含 content 和累积后的 toolCalls
    public func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        guard let request = makeRequest(messages: messages, config: config, tools: tools, apiKey: apiKey) else {
            return AsyncStream { $0.finish() }
        }
        return transport.chunkStream(for: request)
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

    /// 构造 chat 请求：统一 payload（含多模态 content 与 stream_options.include_usage）+ Bearer 鉴权头。
    private func makeRequest(messages: [APIMessage], config: ChatConfig, tools: [ToolDef]?, apiKey: String) -> URLRequest? {
        guard let url = URL(string: APIConfig.deepseekBaseURL + APIConfig.chatEndpoint) else { return nil }
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
            tool_choice: tools == nil ? nil : "auto"
        )
        return body.makeRequest(url: url, headers: ["Authorization": "Bearer \(apiKey)"], includeUsage: true)
    }
}

/// LLM 错误通知名，userInfo["error"] 为 LLMError 实例
public extension Notification.Name {
    static let llmErrorOccurred = Notification.Name("llmErrorOccurred")
}
