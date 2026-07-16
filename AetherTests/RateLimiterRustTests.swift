import XCTest
import AetherRust

/// Rust 令牌桶限流器包装器单元测试。
/// 验证 AetherRustTokenBucket 的 acquire/available/reset 行为。
final class RateLimiterRustTests: XCTestCase {

    private func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - 初始化

    func testInitWithCapacity() {
        let bucket = AetherRustTokenBucket(capacity: 10.0, refillRate: 1.0, nowMs: nowMs())
        let available = bucket.availableTokens(nowMs: nowMs())
        XCTAssertEqual(available, 10.0, accuracy: 0.1, "初始应有满桶令牌")
    }

    // MARK: - acquire

    func testAcquireWithinCapacity() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 10.0, refillRate: 1.0, nowMs: ts)
        let wait = bucket.acquire(5.0, nowMs: ts)
        XCTAssertNil(wait, "在容量内获取应成功（返回 nil）")
        let remaining = bucket.availableTokens(nowMs: ts)
        XCTAssertEqual(remaining, 5.0, accuracy: 0.1, "剩余令牌应为 5")
    }

    func testAcquireExceedsCapacity() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 5.0, refillRate: 1.0, nowMs: ts)
        let wait = bucket.acquire(10.0, nowMs: ts)
        XCTAssertNotNil(wait, "超过容量获取应返回等待时间")
        XCTAssertGreaterThan(wait!, 0, "等待时间应为正数")
    }

    func testAcquireZeroTokens() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 10.0, refillRate: 1.0, nowMs: ts)
        let wait = bucket.acquire(0.0, nowMs: ts)
        XCTAssertNil(wait, "获取 0 个令牌应成功")
    }

    func testAcquireExhaustsBucket() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 3.0, refillRate: 1.0, nowMs: ts)
        // 首次获取 3 个令牌
        let w1 = bucket.acquire(3.0, nowMs: ts)
        XCTAssertNil(w1, "获取 3 个令牌应成功")
        // 再次获取应失败
        let w2 = bucket.acquire(1.0, nowMs: ts)
        XCTAssertNotNil(w2, "耗尽后再次获取应返回等待时间")
    }

    // MARK: - availableTokens

    func testAvailableTokensDecreasesAfterAcquire() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 10.0, refillRate: 1.0, nowMs: ts)
        let before = bucket.availableTokens(nowMs: ts)
        _ = bucket.acquire(3.0, nowMs: ts)
        let after = bucket.availableTokens(nowMs: ts)
        XCTAssertEqual(after, before - 3.0, accuracy: 0.1, "获取后可用令牌应减少")
    }

    // MARK: - reset

    func testResetRestoresCapacity() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 10.0, refillRate: 1.0, nowMs: ts)
        _ = bucket.acquire(8.0, nowMs: ts)
        bucket.reset(nowMs: ts)
        let available = bucket.availableTokens(nowMs: ts)
        XCTAssertEqual(available, 10.0, accuracy: 0.1, "reset 后应恢复满桶")
    }

    func testResetThenAcquire() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 5.0, refillRate: 1.0, nowMs: ts)
        // 耗尽
        _ = bucket.acquire(5.0, nowMs: ts)
        let wait1 = bucket.acquire(1.0, nowMs: ts)
        XCTAssertNotNil(wait1, "耗尽后应被限流")
        // 重置
        bucket.reset(nowMs: ts)
        let wait2 = bucket.acquire(5.0, nowMs: ts)
        XCTAssertNil(wait2, "reset 后应可再次获取")
    }

    // MARK: - 边界条件

    func testZeroCapacity() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 0.0, refillRate: 1.0, nowMs: ts)
        let wait = bucket.acquire(1.0, nowMs: ts)
        XCTAssertNotNil(wait, "容量为 0 时任何获取都应返回等待时间")
    }

    func testZeroRefillRate() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 5.0, refillRate: 0.0, nowMs: ts)
        _ = bucket.acquire(5.0, nowMs: ts)
        let wait = bucket.acquire(1.0, nowMs: ts)
        XCTAssertNotNil(wait, "refillRate=0 时耗尽后应被限流")
    }

    func testAcquireNegativeTokens() {
        let ts = nowMs()
        let bucket = AetherRustTokenBucket(capacity: 10.0, refillRate: 1.0, nowMs: ts)
        let wait = bucket.acquire(-1.0, nowMs: ts)
        XCTAssertNil(wait, "负数请求应被忽略（返回 nil）")
    }
}