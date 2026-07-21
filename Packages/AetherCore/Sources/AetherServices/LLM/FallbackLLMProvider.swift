import Foundation
import os
import AetherFoundation

/// Day 13: 自动降级装饰器。主 provider 抛 LLMError 时自动用备用 provider 重试一次。
/// chat / chatWithTools 路径会降级；embed 路径不降级（避免双倍调用）。
/// lastUsedProvider 暴露实际命中的 provider，供 DebugInfo 展示。
///
/// P1-3: 原实现使用 `nonisolated(unsafe) var` 暴露可变状态，跨 actor 读写无同步保护，
/// 存在数据竞争。现改用 `OSAllocatedUnfairLock` 保护 lastUsedProvider / didFallback，
/// 既保留 `@unchecked Sendable` 兼容性（LLMProvider 协议要求），又满足 Swift 6 严格并发。
public final class FallbackLLMProvider: LLMProvider, @unchecked Sendable {
    /// 主 provider
    private let primary: LLMProvider
    /// 备用 provider
    private let fallback: LLMProvider
    /// 主 provider 对应的 ModelProvider（用于记录 lastUsedProvider）
    private let primaryProvider: ModelProvider
    /// 备用 provider 对应的 ModelProvider
    private let fallbackProvider: ModelProvider

    /// 最近一次请求实际命中的 provider（初值为主 provider，触发降级后改为备用）。
    /// 用 OSAllocatedUnfairLock 保护跨 actor 读写。
    private let lastUsedProviderLock: OSAllocatedUnfairLock<ModelProvider>
    /// 是否在最近一次请求中触发了降级。同上，用锁保护。
    private let didFallbackLock: OSAllocatedUnfairLock<Bool>

    /// 当前实际命中的 provider（线程安全读取）
    public var lastUsedProvider: ModelProvider {
        lastUsedProviderLock.withLock { $0 }
    }

    /// 最近一次请求是否触发了降级（线程安全读取）
    public var didFallback: Bool {
        didFallbackLock.withLock { $0 }
    }

    public init(primary: LLMProvider, fallback: LLMProvider, primaryProvider: ModelProvider, fallbackProvider: ModelProvider) {
        self.primary = primary
        self.fallback = fallback
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.lastUsedProviderLock = OSAllocatedUnfairLock(initialState: primaryProvider)
        self.didFallbackLock = OSAllocatedUnfairLock(initialState: false)
    }

    /// 纯文本 chat 流：先尝试主 provider，若未产出任何内容则降级到备用 provider。
    /// 降级判定：主 provider stream finish 时 yieldedAny 为 false（覆盖 HTTP 错误提前 finish 的场景）。
    public func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                var yieldedAny = false
                let primaryStream = self.primary.chat(messages: messages, config: config, apiKey: apiKey)
                for await content in primaryStream {
                    yieldedAny = true
                    continuation.yield(content)
                }
                if !yieldedAny {
                    // 主 provider 未产出任何内容，触发降级（线程安全写入）
                    self.lastUsedProviderLock.withLock { $0 = self.fallbackProvider }
                    self.didFallbackLock.withLock { $0 = true }
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
    public func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            Task {
                var yieldedAny = false
                let primaryStream = self.primary.chat(messages: messages, config: config, tools: tools, apiKey: apiKey)
                for await chunk in primaryStream {
                    yieldedAny = true
                    continuation.yield(chunk)
                }
                if !yieldedAny {
                    // 主 provider 未产出，降级到 fallback（线程安全写入）
                    self.lastUsedProviderLock.withLock { $0 = self.fallbackProvider }
                    self.didFallbackLock.withLock { $0 = true }
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
    public func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        lastUsedProviderLock.withLock { $0 = primaryProvider }
        didFallbackLock.withLock { $0 = false }
        return try await primary.embed(texts: texts, apiKey: apiKey)
    }
}
