import Foundation
import AetherFoundation
import AetherRust

/// 客户端令牌桶限流器。actor 隔离保证计数线程安全。
/// 调用方（ChatViewModel）在发起 BFF 请求前先 acquireChat/acquireEmbed，耗尽则抛 rateLimited。
///
/// 限流算法已迁移至 Rust（aether-core token-bucket，连续 refill），
/// 统一 Apple/Workers 限流算法。如需回退到纯 Swift 实现，将 `useRust` 置为 false。
public actor RateLimiter {
    /// 切换开关：true 走 Rust 核心，false 走下方纯 Swift 兜底实现。
    private static let useRust = true

    /// 当前可用 chat 令牌数
    private var chatTokens: Int
    /// 当前可用 embed 令牌数
    private var embedTokens: Int
    /// chat 接口每分钟令牌上限
    private let chatPerMin: Int
    /// embed 接口每分钟令牌上限
    private let embedPerMin: Int
    /// 上一次令牌补充时间
    private var lastRefillAt: Date

    /// Rust 令牌桶（chat），refill_rate = chatPerMin / 60 tokens/sec
    private var chatBucket: AetherRustTokenBucket?
    /// Rust 令牌桶（embed），refill_rate = embedPerMin / 60 tokens/sec
    private var embedBucket: AetherRustTokenBucket?

    /// 构造限流器
    /// - Parameters:
    ///   - chatPerMin: chat 每分钟令牌数（默认 20）
    ///   - embedPerMin: embed 每分钟令牌数（默认 10）
    public init(chatPerMin: Int = 20, embedPerMin: Int = 10) {
        self.chatPerMin = chatPerMin
        self.embedPerMin = embedPerMin
        self.chatTokens = chatPerMin
        self.embedTokens = embedPerMin
        self.lastRefillAt = Date()
        if Self.useRust {
            let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
            self.chatBucket = AetherRustTokenBucket(
                capacity: Double(chatPerMin),
                refillRate: Double(chatPerMin) / 60.0,
                nowMs: nowMs
            )
            self.embedBucket = AetherRustTokenBucket(
                capacity: Double(embedPerMin),
                refillRate: Double(embedPerMin) / 60.0,
                nowMs: nowMs
            )
        }
    }

    /// 申请一个 chat 令牌。令牌耗尽时抛 rateLimited。
    public func acquireChat() throws {
        if Self.useRust, let bucket = chatBucket {
            let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
            if let retryAfter = bucket.acquire(1.0, nowMs: nowMs) {
                throw LLMError.rateLimited(retryAfter: retryAfter.rounded(.up))
            }
            return
        }
        try acquireChatSwift()
    }

    /// 申请一个 embed 令牌。令牌耗尽时抛 rateLimited。
    public func acquireEmbed() throws {
        if Self.useRust, let bucket = embedBucket {
            let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
            if let retryAfter = bucket.acquire(1.0, nowMs: nowMs) {
                throw LLMError.rateLimited(retryAfter: retryAfter.rounded(.up))
            }
            return
        }
        try acquireEmbedSwift()
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    /// Swift 兜底：申请 chat 令牌。
    private func acquireChatSwift() throws {
        refillIfNeeded()
        guard chatTokens > 0 else { throw LLMError.rateLimited(retryAfter: 60) }
        chatTokens -= 1
    }

    /// Swift 兜底：申请 embed 令牌。
    private func acquireEmbedSwift() throws {
        refillIfNeeded()
        guard embedTokens > 0 else { throw LLMError.rateLimited(retryAfter: 60) }
        embedTokens -= 1
    }

    /// 距上次补充满 60 秒则重置两类令牌至上限（滑动窗口式补充）。
    private func refillIfNeeded() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillAt)
        if elapsed >= 60 {
            chatTokens = chatPerMin
            embedTokens = embedPerMin
            lastRefillAt = now
        }
    }
}
