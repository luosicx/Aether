import Foundation
import AetherRustC

/// Swift 友好的 Rust 令牌桶限流器包装。
///
/// 将 `RateLimiter.swift`（原"60 秒整桶重置"简化算法）迁移至 Rust
/// `aether-core` token-bucket（连续 refill，每秒按比例补充）。
/// 调用方传入当前时间戳，避免 Rust 侧依赖 `std::time::Instant`
/// （WASM32 不可用）。
///
/// 线程安全契约：实例应仅在单一 actor 中使用（如 `RateLimiter` actor 持有
/// `chatBucket` / `embedBucket`）。跨 actor 共享需在调用点加 NSLock，
/// 否则并发 `acquire` 会导致令牌计数错乱（可能突破限流上限）。
/// Rust FFI 层（`aether_rate_limiter_acquire`）未加 Mutex，依赖外部串行化。
public final class AetherRustTokenBucket: @unchecked Sendable {
    private let state: OpaquePointer

    /// 创建令牌桶。初始满桶。
    /// - Parameters:
    ///   - capacity: 桶容量（最大令牌数）
    ///   - refillRate: 每秒补充令牌数
    ///   - nowMs: 当前 epoch 毫秒时间戳
    public init(capacity: Double, refillRate: Double, nowMs: UInt64) {
        state = aether_rate_limiter_new(capacity, refillRate, nowMs)
    }

    deinit {
        aether_rate_limiter_free(state)
    }

    /// 尝试获取 `n` 个令牌。
    /// - Returns: 成功返回 `nil`，失败返回预估等待秒数。
    public func acquire(_ n: Double, nowMs: UInt64) -> Double? {
        let result = aether_rate_limiter_acquire(state, n, nowMs)
        return result > 0 ? result : nil
    }

    /// 当前可用令牌数（触发补充后）。
    public func availableTokens(nowMs: UInt64) -> Double {
        aether_rate_limiter_available(state, nowMs)
    }

    /// 重置桶到满容量。
    public func reset(nowMs: UInt64) {
        aether_rate_limiter_reset(state, nowMs)
    }
}
