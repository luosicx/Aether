import Foundation
import AetherFoundation

/// Day 15: 客户端令牌桶限流器。actor 隔离保证计数线程安全。
/// 注意：本类型仅做令牌扣减，不包装 LLMProvider（非装饰器）。
/// 调用方（ChatViewModel）在发起 BFF 请求前先 acquireChat/acquireEmbed，耗尽则抛 rateLimited。
public actor RateLimiter {
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
    }

    /// 申请一个 chat 令牌。令牌耗尽时抛 rateLimited（建议 60 秒后重试）。
    public func acquireChat() throws {
        refillIfNeeded()
        guard chatTokens > 0 else { throw LLMError.rateLimited(retryAfter: 60) }
        chatTokens -= 1
    }

    /// 申请一个 embed 令牌。令牌耗尽时抛 rateLimited（建议 60 秒后重试）。
    public func acquireEmbed() throws {
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
