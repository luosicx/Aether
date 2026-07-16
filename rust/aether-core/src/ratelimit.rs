//! 令牌桶限流器：标准连续 refill 算法。
//!
//! 统一 Apple（`RateLimiter.swift`，原"60 秒整桶重置"）与
//! CloudflareWorkers（`ratelimit.js`，原固定窗口计数器）的限流算法。
//!
//! 设计要点：调用方传入当前时间戳（epoch ms），避免依赖 `std::time::Instant`
//! （该类型在 `wasm32-unknown-unknown` 不可用）。

/// 令牌桶限流器。
///
/// 桶容量 `capacity`，每秒补充 `refill_rate` 个令牌（连续补充，非整桶重置）。
/// `acquire` 时先按时间差补充令牌（上限为 capacity），再尝试扣减。
pub struct TokenBucket {
    capacity: f64,
    tokens: f64,
    refill_rate: f64,
    last_refill_ms: u64,
}

impl TokenBucket {
    /// 创建令牌桶，初始令牌数 = 容量（满桶）。
    ///
    /// - `capacity`: 桶容量（最大令牌数）
    /// - `refill_rate`: 每秒补充令牌数
    /// - `now_ms`: 当前 epoch 毫秒时间戳
    pub fn new(capacity: f64, refill_rate: f64, now_ms: u64) -> Self {
        Self {
            capacity,
            tokens: capacity,
            refill_rate,
            last_refill_ms: now_ms,
        }
    }

    /// 尝试获取 `n` 个令牌。
    ///
    /// 成功返回 `Ok(())`，失败返回 `Err(retry_after_seconds)`
    /// （距下次有足够令牌的预估等待秒数）。
    /// `n=0` 恒成功（纯补充）。
    pub fn acquire(&mut self, n: f64, now_ms: u64) -> Result<(), f64> {
        self.refill(now_ms);
        if self.tokens >= n {
            self.tokens -= n;
            Ok(())
        } else {
            // 计算还需多少令牌 + 按补充速率换算为秒
            let deficit = n - self.tokens;
            let retry_after = if self.refill_rate > 0.0 {
                (deficit / self.refill_rate).ceil()
            } else {
                // refill_rate=0 愸不补充，返回一个较大的值
                60.0
            };
            Err(retry_after.max(1.0))
        }
    }

    /// 按时间差补充令牌（上限为 capacity）。
    fn refill(&mut self, now_ms: u64) {
        if now_ms <= self.last_refill_ms {
            return;
        }
        let elapsed_secs = (now_ms - self.last_refill_ms) as f64 / 1000.0;
        let added = elapsed_secs * self.refill_rate;
        self.tokens = (self.tokens + added).min(self.capacity);
        self.last_refill_ms = now_ms;
    }

    /// 当前可用令牌数（触发补充后）。
    pub fn available_tokens(&mut self, now_ms: u64) -> f64 {
        self.refill(now_ms);
        self.tokens
    }

    /// 重置桶到满容量。
    pub fn reset(&mut self, now_ms: u64) {
        self.tokens = self.capacity;
        self.last_refill_ms = now_ms;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: u64 = 1_000_000; // 基准时间

    #[test]
    fn new_starts_full() {
        let b = TokenBucket::new(10.0, 1.0, T0);
        // 内部 tokens = capacity = 10
        let mut b = b;
        assert_eq!(b.available_tokens(T0), 10.0);
    }

    #[test]
    fn acquire_within_capacity_succeeds() {
        let mut b = TokenBucket::new(5.0, 1.0, T0);
        for _ in 0..5 {
            assert!(b.acquire(1.0, T0).is_ok());
        }
    }

    #[test]
    fn acquire_exceeding_capacity_fails() {
        let mut b = TokenBucket::new(5.0, 1.0, T0);
        for _ in 0..5 {
            b.acquire(1.0, T0).unwrap();
        }
        let err = b.acquire(1.0, T0).unwrap_err();
        assert!(err >= 1.0);
    }

    #[test]
    fn refill_adds_tokens_over_time() {
        let mut b = TokenBucket::new(10.0, 10.0, T0); // 10 tokens/sec
                                                      // 耗尽
        for _ in 0..10 {
            b.acquire(1.0, T0).unwrap();
        }
        // 1 秒后应补充 10 个
        let result = b.acquire(1.0, T0 + 1000);
        assert!(result.is_ok());
    }

    #[test]
    fn refill_capped_at_capacity() {
        let mut b = TokenBucket::new(10.0, 100.0, T0); // 100 tokens/sec, cap 10
        b.tokens = 5.0;
        // 10 秒后应补充 1000 但 cap 在 10
        let avail = b.available_tokens(T0 + 10_000);
        assert_eq!(avail, 10.0);
    }

    #[test]
    fn retry_after_estimates_wait_time() {
        // capacity=5, rate=2/sec → 耗尽后需 0.5 秒补 1 个
        let mut b = TokenBucket::new(5.0, 2.0, T0);
        for _ in 0..5 {
            b.acquire(1.0, T0).unwrap();
        }
        let retry = b.acquire(1.0, T0).unwrap_err();
        // deficit=1, rate=2 → 0.5 → ceil → 1
        assert_eq!(retry, 1.0);
    }

    #[test]
    fn retry_after_for_large_deficit() {
        // capacity=5, rate=1/sec → 耗尽后需 5 个，等 5 秒
        let mut b = TokenBucket::new(5.0, 1.0, T0);
        for _ in 0..5 {
            b.acquire(1.0, T0).unwrap();
        }
        let retry = b.acquire(5.0, T0).unwrap_err();
        assert_eq!(retry, 5.0);
    }

    #[test]
    fn zero_capacity_immediately_blocks() {
        let mut b = TokenBucket::new(0.0, 1.0, T0);
        assert!(b.acquire(1.0, T0).is_err());
    }

    #[test]
    fn zero_n_always_succeeds() {
        let mut b = TokenBucket::new(0.0, 0.0, T0);
        assert!(b.acquire(0.0, T0).is_ok());
    }

    #[test]
    fn zero_refill_rate_never_replenishes() {
        let mut b = TokenBucket::new(2.0, 0.0, T0);
        b.acquire(2.0, T0).unwrap();
        assert!(b.acquire(1.0, T0 + 999_999).is_err());
    }

    #[test]
    fn partial_refill_allows_partial_acquire() {
        // capacity=10, rate=10/sec
        let mut b = TokenBucket::new(10.0, 10.0, T0);
        for _ in 0..10 {
            b.acquire(1.0, T0).unwrap();
        }
        // 0.5 秒后补充 5 个
        assert!(b.acquire(5.0, T0 + 500).is_ok());
        // 再要 1 个失败
        assert!(b.acquire(1.0, T0 + 500).is_err());
    }

    #[test]
    fn reset_refills_to_capacity() {
        let mut b = TokenBucket::new(10.0, 1.0, T0);
        for _ in 0..10 {
            b.acquire(1.0, T0).unwrap();
        }
        b.reset(T0 + 5000);
        assert_eq!(b.available_tokens(T0 + 5000), 10.0);
    }

    #[test]
    fn backward_time_no_refill() {
        // 时间倒退不应补充令牌
        let mut b = TokenBucket::new(10.0, 100.0, T0);
        b.tokens = 5.0;
        assert_eq!(b.available_tokens(T0 - 1000), 5.0);
    }

    #[test]
    fn multiple_acquires_track_correctly() {
        // capacity=3, rate=3/sec（每秒补 3 个）
        let mut b = TokenBucket::new(3.0, 3.0, T0);
        assert!(b.acquire(1.0, T0).is_ok());
        assert!(b.acquire(1.0, T0).is_ok());
        assert!(b.acquire(1.0, T0).is_ok());
        assert!(b.acquire(1.0, T0).is_err());
        // 1 秒后补满
        assert!(b.acquire(3.0, T0 + 1000).is_ok());
    }

    #[test]
    fn fractional_tokens_supported() {
        // capacity=1, rate=0.5/sec
        let mut b = TokenBucket::new(1.0, 0.5, T0);
        b.acquire(1.0, T0).unwrap();
        // 2 秒后补 1 个
        assert!(b.acquire(1.0, T0 + 2000).is_ok());
        assert!(b.acquire(1.0, T0 + 2000).is_err());
    }

    #[test]
    fn acquire_more_than_capacity_never_succeeds() {
        // capacity=5, 请求 10
        let mut b = TokenBucket::new(5.0, 10.0, T0);
        let retry = b.acquire(10.0, T0).unwrap_err();
        // deficit=5, rate=10 → 0.5 → ceil → 1
        assert_eq!(retry, 1.0);
        // 但即使等 1 秒，补充 10 个 + 原有 5 个 = cap 5，仍不足 10
        assert!(b.acquire(10.0, T0 + 1000).is_err());
    }
}
