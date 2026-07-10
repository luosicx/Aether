import Foundation

/// Day 13: 自动降级装饰器。主 provider 抛 LLMError 时自动用备用 provider 重试一次。
/// chat / chatWithTools 路径会降级；embed 路径不降级（避免双倍调用）。
/// lastUsedProvider 暴露实际命中的 provider，供 DebugInfo 展示。
final class FallbackLLMProvider: LLMProvider {
    /// 主 provider
    private let primary: LLMProvider
    /// 备用 provider
    private let fallback: LLMProvider
    /// 主 provider 对应的 ModelProvider（用于记录 lastUsedProvider）
    private let primaryProvider: ModelProvider
    /// 备用 provider 对应的 ModelProvider
    private let fallbackProvider: ModelProvider

    /// 最近一次请求实际命中的 provider（初值为主 provider，触发降级后改为备用）
    /// nonisolated(unsafe) 适配 Swift 6 minimal（跨 actor 读写需调用方自行同步，本类只在 LLMProvider 方法内写入）
    nonisolated(unsafe) private(set) var lastUsedProvider: ModelProvider

    /// 是否在最近一次请求中触发了降级
    nonisolated(unsafe) private(set) var didFallback: Bool = false

    init(primary: LLMProvider, fallback: LLMProvider, primaryProvider: ModelProvider, fallbackProvider: ModelProvider) {
        self.primary = primary
        self.fallback = fallback
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.lastUsedProvider = primaryProvider
    }

    /// 纯文本 chat 流：先尝试主 provider，若未产出任何内容则降级到备用 provider。
    /// 降级判定：主 provider stream finish 时 yieldedAny 为 false（覆盖 HTTP 错误提前 finish 的场景）。
    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                var yieldedAny = false
                let primaryStream = self.primary.chat(messages: messages, config: config, apiKey: apiKey)
                for await content in primaryStream {
                    yieldedAny = true
                    continuation.yield(content)
                }
                if !yieldedAny {
                    // 主 provider 未产出任何内容，触发降级
                    self.lastUsedProvider = self.fallbackProvider
                    self.didFallback = true
                    let fallbackStream = self.fallback.chat(messages: messages, config: config, apiKey: apiKey)
                    for await content in fallbackStream {
                        continuation.yield(content)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// 带工具调用 chat 流：降级逻辑与纯文本路径一致。
    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            Task {
                var yieldedAny = false
                let primaryStream = self.primary.chat(messages: messages, config: config, tools: tools, apiKey: apiKey)
                for await chunk in primaryStream {
                    yieldedAny = true
                    continuation.yield(chunk)
                }
                if !yieldedAny {
                    // 主 provider 未产出，降级到 fallback
                    self.lastUsedProvider = self.fallbackProvider
                    self.didFallback = true
                    let fallbackStream = self.fallback.chat(messages: messages, config: config, tools: tools, apiKey: apiKey)
                    for await chunk in fallbackStream {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// embed 路径不降级，直接调用主 provider
    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        lastUsedProvider = primaryProvider
        didFallback = false
        return try await primary.embed(texts: texts, apiKey: apiKey)
    }
}
