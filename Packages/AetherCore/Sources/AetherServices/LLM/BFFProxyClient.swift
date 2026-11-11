import Foundation
import AetherFoundation

/// BFF 代理客户端，实现 LLMProvider 协议。
/// 将设备端请求转发到 BFF 网关（Cloudflare Workers），由服务端持有上游 API Key，
/// 设备仅携带 X-BFF-Token 鉴权。请求体结构与 DeepSeekClient 一致，
/// 网络层行为（超时/取消/错误通知）统一由 StreamTransport 承担。
/// nonisolated 设计允许跨 actor 调用。
///
/// P1-12 (H-S1): 当 `config.pinnedSPKIHashes` 非空时，自动创建带 `CertificatePinningDelegate`
/// 的 URLSession 启用 SSL Pinning（防止 MITM）。pin 为空时使用注入的 session（默认 .shared）。
nonisolated public final class BFFProxyClient: LLMProvider, @unchecked Sendable {
    /// 路由目标上游供应商（写入 X-Provider Header，服务端据此选择上游 key/endpoint）
    private let provider: ModelProvider
    /// BFF 配置（endpoint / token / 限流参数 / SSL pin）
    private let config: BFFConfig
    /// URLSession（启用 Pinning 时为带 delegate 的实例；否则使用注入的 session）
    private let session: URLSession
    /// 统一 SSE 传输层（HTTP 错误映射走 BFF 语义）
    private let transport: StreamTransport
    /// Pinning delegate 强引用，防止 URLSession 释放后被回收（仅 Pinning 启用时持有）
    private let pinningDelegate: CertificatePinningDelegate?

    /// 构造 BFF 代理客户端
    /// - Parameters:
    ///   - provider: 路由目标供应商
    ///   - config: BFF 配置（含 pinnedSPKIHashes）
    ///   - session: URLSession（默认 .shared；当 config.pinnedSPKIHashes 非空时本参数被忽略，
    ///     改用带 CertificatePinningDelegate 的新实例）
    public init(provider: ModelProvider, config: BFFConfig, session: URLSession = .shared) {
        self.provider = provider
        self.config = config
        // P1-12: 配置了 SPKI pin 时创建带 delegate 的 URLSession
        let resolvedSession: URLSession
        if config.isSSLPinningEnabled {
            let delegate = CertificatePinningDelegate(pinnedHashes: config.pinnedSPKIHashes)
            self.pinningDelegate = delegate
            resolvedSession = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
        } else {
            self.pinningDelegate = nil
            resolvedSession = session
        }
        self.session = resolvedSession
        self.transport = StreamTransport(session: resolvedSession, httpErrorMapper: { http, body in
            Self.mapHTTPError(http, body: body)
        })
    }

    /// 纯文本 chat 流，返回 AsyncStream<String>，逐 chunk yield 文本内容
    public func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        // P1-11 (H-S5): 客户端 TTL 检查——Token 过期则不发请求，发通知并 finish
        if self.config.isTokenExpired { return expiredTokenStream() }
        guard let request = makeRequest(messages: messages, config: config, tools: nil) else {
            return AsyncStream { $0.finish() }
        }
        return transport.textStream(for: request)
    }

    /// 带工具调用 chat 流，返回 AsyncStream<ParsedChunk>，yield 含 content 和累积后的 toolCalls
    public func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        if self.config.isTokenExpired { return expiredTokenStream() }
        guard let request = makeRequest(messages: messages, config: config, tools: tools) else {
            return AsyncStream { $0.finish() }
        }
        return transport.chunkStream(for: request)
    }

    /// 批量文本嵌入。空入参短路返回空数组。HTTP 非 2xx 抛 LLMError 并发 .llmErrorOccurred 通知。
    /// 返回按 index 排序的向量数组。
    /// 注意：BFF 模式下 apiKey 参数不使用（服务端持有上游 key）。
    public func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        // P1-11 (H-S5): 客户端 TTL 检查——Token 过期则拒绝发送请求
        if config.isTokenExpired {
            let err = LLMError.llmErrorOccurred(NSLocalizedString("BFF Token 已过期，请在设置中重新设置", comment: ""))
            await MainActor.run {
                NotificationCenter.default.post(name: .llmErrorOccurred, object: nil, userInfo: ["error": err])
            }
            throw err
        }
        // BFF 模式下 apiKey 不使用（服务端持有上游 key）
        let body: [String: Any] = [
            "model": provider.defaultEmbeddingModel,
            "input": texts
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let endpointURL = config.endpointURL,
              let url = URL(string: endpointURL.appending(path: "v1/embeddings").absoluteString) else {
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
                let err = Self.mapHTTPError(http, body: String(data: data, encoding: .utf8) ?? "")
                await StreamTransport.report(err)
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

    /// 构造 chat 请求（含工具），转交 StreamTransport。BFF 模式下 apiKey 不使用（服务端持有上游 key）。
    /// 走透明代理路由（OpenAI envelope），不附带 stream_options（由上游/BFF 决定 usage 行为）。
    private func makeRequest(messages: [APIMessage], config: ChatConfig, tools: [ToolDef]?) -> URLRequest? {
        guard let endpointURL = self.config.endpointURL,
              let url = URL(string: endpointURL.appending(path: "v1/chat/completions").absoluteString) else {
            return nil
        }
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
        return body.makeRequest(
            url: url,
            headers: [
                "X-BFF-Token": self.config.userToken,
                "X-Provider": provider.rawValue
            ],
            includeUsage: false
        )
    }

    /// Token 过期时的空流：发通知后立即结束。
    private func expiredTokenStream<T>() -> AsyncStream<T> {
        AsyncStream { continuation in
            let task = Task {
                let err = LLMError.llmErrorOccurred(NSLocalizedString("BFF Token 已过期，请在设置中重新设置", comment: ""))
                await StreamTransport.report(err)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 把 BFF HTTP 错误映射为 LLMError（纯函数，通知由 StreamTransport / embed 发出）。
    /// - 401 → BFF Token 无效
    /// - 429 → 解析 Retry-After Header → rateLimited
    /// - 5xx → BFF 服务异常
    /// - 其他 → apiError
    static func mapHTTPError(_ http: HTTPURLResponse, body: String) -> LLMError {
        switch http.statusCode {
        case 401:
            return .llmErrorOccurred(NSLocalizedString("BFF Token 无效", comment: ""))
        case 429:
            // 解析 Retry-After Header（秒），缺省 60
            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            return .rateLimited(retryAfter: max(retryAfter, 1))
        case 500...599:
            return .llmErrorOccurred(NSLocalizedString("BFF 服务异常", comment: ""))
        default:
            return .apiError(code: http.statusCode, message: "BFF HTTP \(http.statusCode)")
        }
    }
}
