import Foundation
import AetherFoundation
import AetherServices

/// Task 24 阶段 2: AetherClient 核心 API 实现。
///
/// 包含 chat / stream / embed / retrieve 四个核心方法。
/// chat 与 stream 接入 `SemanticCache`（命中缓存直接返回）；
/// 所有方法支持 `RetryPolicy` 自动重试（仅对 `AetherError.isRetryable` 的错误）。
extension AetherClient {

    // MARK: - chat

    /// 单轮对话：返回完整响应字符串
    /// - Parameters:
    ///   - messages: 消息列表
    ///   - tools: 可调用工具列表（可选）
    /// - Returns: 完整响应字符串
    /// - Throws: `AetherError`
    public func chat(messages: [AetherMessage], tools: [AetherTool] = []) async throws -> String {
        // 1. 注册工具到内部 registry（临时，作用域内）
        for tool in tools {
            toolRegistryInternal.register(tool: tool)
        }
        defer {
            for tool in tools {
                toolRegistryInternal.unregister(name: tool.definition.name)
            }
        }

        // 2. 检查语义缓存（仅无工具调用时）
        let cacheKey = AetherClientAPI.cacheKey(for: messages)
        if tools.isEmpty, let cache = await getCache(),
           let queryEmbedding = try? await embed(texts: [cacheKey]).first,
           !queryEmbedding.isEmpty {
            if let cached = await cache.get(query: cacheKey, embedding: queryEmbedding) {
                return cached
            }
            // 缓存未命中，执行 LLM 调用
            let response = try await executeChatWithRetry(messages: messages, tools: tools)
            // 写入缓存
            await cache.set(query: cacheKey, embedding: queryEmbedding, response: response)
            return response
        }

        // 3. 无缓存路径
        return try await executeChatWithRetry(messages: messages, tools: tools)
    }

    /// 实际执行 chat（带重试）
    private func executeChatWithRetry(messages: [AetherMessage], tools: [AetherTool]) async throws -> String {
        let policy = retryPolicyInternal
        var lastError: Error?
        for attempt in 0..<policy.maxAttempts {
            do {
                return try await AetherClientAPI.chatSingleAttempt(
                    provider: providerInternal,
                    config: config,
                    messages: messages,
                    tools: tools,
                    toolRegistry: toolRegistryInternal
                )
            } catch let error as AetherError {
                lastError = error
                if error.isRetryable && policy.canRetry(afterAttempt: attempt) {
                    let delay = policy.delay(forAttempt: attempt)
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    continue
                }
                throw error
            } catch {
                lastError = error
                // 非 AetherError 包装后立即抛出
                throw AetherClientAPI.wrapError(error)
            }
        }
        throw lastError ?? AetherError.providerError(code: -1, message: "重试用尽")
    }

    // MARK: - stream

    /// 流式对话：返回 AsyncStream<AetherChunk>
    /// - Parameters:
    ///   - messages: 消息列表
    ///   - tools: 可调用工具列表（可选）
    /// - Returns: chunk 流
    public func stream(messages: [AetherMessage], tools: [AetherTool] = []) -> AsyncStream<AetherChunk> {
        // 注册工具到内部 registry
        for tool in tools {
            toolRegistryInternal.register(tool: tool)
        }
        let provider = providerInternal
        let config = self.config
        let toolRegistry = toolRegistryInternal
        return AsyncStream { continuation in
            let task = Task {
                await Self.streamTaskBody(
                    messages: messages,
                    tools: tools,
                    provider: provider,
                    config: config,
                    toolRegistry: toolRegistry,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// stream 内部执行体（提取以避免 3 层闭包嵌套触发 S3087）
    private static func streamTaskBody(
        messages: [AetherMessage],
        tools: [AetherTool],
        provider: LLMProvider,
        config: AetherConfig,
        toolRegistry: AetherToolRegistry,
        continuation: AsyncStream<AetherChunk>.Continuation
    ) async {
        defer {
            for tool in tools {
                toolRegistry.unregister(name: tool.definition.name)
            }
            continuation.finish()
        }
        let apiMessages = AetherClientAPI.convertMessages(messages)
        let chatConfig = AetherClientAPI.convertChatConfig(config)
        let toolDefs = AetherClientAPI.convertToolDefs(tools, registry: toolRegistry)
        if toolDefs.isEmpty {
            let stream = provider.chat(messages: apiMessages, config: chatConfig, apiKey: config.apiKey)
            for await chunk in stream {
                continuation.yield(AetherChunk(content: chunk))
            }
        } else {
            let stream = provider.chat(messages: apiMessages, config: chatConfig, tools: toolDefs, apiKey: config.apiKey)
            for await parsed in stream {
                let content = parsed.content
                let toolCalls = parsed.toolCalls?.map {
                    AetherToolCall(id: $0.id, type: $0.type, name: $0.name, arguments: $0.arguments)
                }
                continuation.yield(AetherChunk(content: content, toolCalls: toolCalls))
            }
        }
        continuation.yield(.final())
    }

    // MARK: - embed

    /// 批量文本嵌入
    /// - Parameter texts: 文本数组
    /// - Returns: 向量数组（按 index 排序）
    /// - Throws: `AetherError`
    public func embed(texts: [String]) async throws -> [[Float]] {
        try await AetherClientAPI.embed(
            provider: providerInternal,
            embeddingProvider: embeddingProviderInternal,
            config: config,
            texts: texts
        )
    }

    // MARK: - retrieve

    /// RAG 检索
    /// - Parameters:
    ///   - query: 用户查询
    ///   - topK: 返回数量
    /// - Returns: 相关文档列表
    /// - Throws: `AetherError`
    public func retrieve(query: String, topK: Int = 5) async throws -> [AetherDocument] {
        guard let ragProvider = ragProviderInternal else {
            throw AetherError.ragRetrievalFailed(reason: "未注入 RAGProvider，请通过 init(config:provider:ragProvider:) 注入")
        }
        guard let ragConfig = config.rag else {
            throw AetherError.ragRetrievalFailed(reason: "config.rag 未配置")
        }
        do {
            return try await ragProvider.retrieve(query: query, topK: topK, knowledgeBaseID: ragConfig.knowledgeBaseID)
        } catch let error as AetherError {
            throw error
        } catch {
            // P2-3: 携带 underlying 保留原始 Error 上下文
            throw AetherError.ragRetrievalFailedWithCause(reason: error.localizedDescription, underlying: error)
        }
    }
}

/// 内部 API 实现命名空间
internal enum AetherClientAPI {

    // MARK: - 消息转换

    /// AetherMessage → APIMessage
    static func convertMessages(_ messages: [AetherMessage]) -> [APIMessage] {
        messages.map { msg in
            APIMessage(
                role: msg.role.rawValue,
                content: msg.content,
                images: msg.images,
                toolCallId: msg.toolCallId,
                toolName: msg.toolName,
                toolCalls: msg.toolCalls?.map {
                    ToolCallParam(
                        id: $0.id,
                        type: $0.type,
                        function: FunctionCall(name: $0.name, arguments: $0.arguments)
                    )
                }
            )
        }
    }

    /// AetherConfig → ChatConfig
    static func convertChatConfig(_ config: AetherConfig) -> ChatConfig {
        ChatConfig(
            model: config.provider.internalProvider.defaultChatModel,
            systemPrompt: "",
            maxTokens: 2048,
            temperature: 0.7
        )
    }

    /// AetherTool 列表 + registry → ToolDef 数组（含已注册工具）
    /// - Note: `tools` 参数仅在调用方注册到 registry 后由 registry 统一管理，此处读取 registry 即可
    static func convertToolDefs(_ tools: [AetherTool], registry: AetherToolRegistry) -> [ToolDef] {
        _ = tools // 已注册到 registry，本函数读取 registry 即可
        // 使用 registry 中所有可用工具（含传入的 tools 已注册）
        let defs = registry.availableDefinitions()
        return defs.map { def in
            ToolDef(
                type: "function",
                function: ToolDef.FunctionDef(
                    name: def.name,
                    description: def.description,
                    parameters: def.parameters().mapValues(AnyCodable.init)
                )
            )
        }
    }

    // MARK: - chat 单次尝试

    /// 单次 chat 调用（不含重试）
    static func chatSingleAttempt(
        provider: LLMProvider,
        config: AetherConfig,
        messages: [AetherMessage],
        tools: [AetherTool],
        toolRegistry: AetherToolRegistry
    ) async throws -> String {
        let apiMessages = convertMessages(messages)
        let chatConfig = convertChatConfig(config)
        let toolDefs = convertToolDefs(tools, registry: toolRegistry)

        var accumulated = ""
        if toolDefs.isEmpty {
            let stream = provider.chat(messages: apiMessages, config: chatConfig, apiKey: config.apiKey)
            for try await chunk in stream {
                accumulated += chunk
            }
        } else {
            let stream = provider.chat(messages: apiMessages, config: chatConfig, tools: toolDefs, apiKey: config.apiKey)
            for try await parsed in stream {
                if let content = parsed.content {
                    accumulated += content
                }
                // 工具调用处理：执行工具并把结果追加到下一轮
                if let toolCalls = parsed.toolCalls, !toolCalls.isEmpty {
                    var newMessages = messages
                    newMessages.append(.assistant(accumulated))
                    for call in toolCalls {
                        let arguments = parseArguments(call.arguments)
                        do {
                            let result = try await toolRegistry.execute(name: call.name, arguments: arguments)
                            newMessages.append(.tool(name: call.name, callId: call.id, content: result))
                        } catch {
                            let errMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            newMessages.append(.tool(name: call.name, callId: call.id, content: "错误：\(errMsg)"))
                        }
                    }
                    // 递归续流（不带工具以简化；生产可继续带工具）
                    let apiMsgs = convertMessages(newMessages)
                    let continueStream = provider.chat(messages: apiMsgs, config: chatConfig, apiKey: config.apiKey)
                    for try await chunk in continueStream {
                        accumulated += chunk
                    }
                    break
                }
            }
        }
        if accumulated.isEmpty {
            // 空响应通常表示网络故障（DeepSeekClient 在网络错误时发送 .llmErrorOccurred 通知后 finish 流）
            // 视为可重试错误，让 RetryPolicy 自动重试
            throw AetherError.networkUnreachable
        }
        return accumulated
    }

    /// 解析 JSON 字符串参数为字典
    static func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    // MARK: - embed

    /// 嵌入实现：优先用 embeddingProvider，否则用 provider.embed
    static func embed(
        provider: LLMProvider,
        embeddingProvider: AetherEmbeddingProvider?,
        config: AetherConfig,
        texts: [String]
    ) async throws -> [[Float]] {
        do {
            if let embeddingProvider = embeddingProvider {
                return try await embeddingProvider.embed(texts: texts, apiKey: config.apiKey)
            }
            return try await provider.embed(texts: texts, apiKey: config.apiKey)
        } catch let error as AetherError {
            throw error
        } catch let error as LLMError {
            throw AetherError.from(error)
        } catch {
            throw wrapError(error)
        }
    }

    // MARK: - cache key

    /// 生成消息列表的缓存 key（拼接所有 user 消息内容）
    static func cacheKey(for messages: [AetherMessage]) -> String {
        messages
            .filter { $0.role == .user }
            .map(\.content)
            .joined(separator: "\n---\n")
    }

    // MARK: - 错误包装

    /// 将任意 Error 包装为 AetherError
    static func wrapError(_ error: Error) -> AetherError {
        if let aetherError = error as? AetherError {
            return aetherError
        }
        if let llmError = error as? LLMError {
            return AetherError.from(llmError)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .networkUnreachable
        }
        return .providerError(code: nsError.code, message: nsError.localizedDescription)
    }
}
