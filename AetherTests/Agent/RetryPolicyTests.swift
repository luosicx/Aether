import XCTest
@testable import Aether

/// Task 20 阶段 3: RetryPolicy 单元测试
///
/// 覆盖：
/// - 默认参数（maxAttempts=3 / initialDelay=1.0 / backoffMultiplier=2.0）
/// - 自定义参数
/// - delay(forAttempt:) 指数退避计算（1s/2s/4s）
/// - backoffSequence() 退避序列
/// - canRetry(afterAttempt:) 边界判断
/// - 参数下限保护（maxAttempts < 1、initialDelay < 0、backoffMultiplier < 1.0）
/// - Sendable 合规性
final class RetryPolicyTests: XCTestCase {

    // MARK: - 默认参数

    /// 默认策略参数正确
    func testDefaultParameters() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.initialDelay, 1.0)
        XCTAssertEqual(policy.backoffMultiplier, 2.0)
    }

    /// `RetryPolicy()` 等同于 `.defaultPolicy`
    func testInitDefaultsEqualDefault() {
        let policy = RetryPolicy()
        XCTAssertEqual(policy.maxAttempts, RetryPolicy.defaultPolicy.maxAttempts)
        XCTAssertEqual(policy.initialDelay, RetryPolicy.defaultPolicy.initialDelay)
        XCTAssertEqual(policy.backoffMultiplier, RetryPolicy.defaultPolicy.backoffMultiplier)
    }

    // MARK: - 自定义参数

    /// 自定义参数正确存储
    func testCustomParameters() {
        let policy = RetryPolicy(maxAttempts: 5, initialDelay: 0.5, backoffMultiplier: 3.0)
        XCTAssertEqual(policy.maxAttempts, 5)
        XCTAssertEqual(policy.initialDelay, 0.5)
        XCTAssertEqual(policy.backoffMultiplier, 3.0)
    }

    // MARK: - delay(forAttempt:)

    /// 默认策略退避序列：1s → 2s → 4s
    func testDelayForAttemptWithDefaultPolicy() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertEqual(policy.delay(forAttempt: 0), 1.0, "attempt 0 → 1s")
        XCTAssertEqual(policy.delay(forAttempt: 1), 2.0, "attempt 1 → 2s")
        XCTAssertEqual(policy.delay(forAttempt: 2), 4.0, "attempt 2 → 4s")
        XCTAssertEqual(policy.delay(forAttempt: 3), 8.0, "attempt 3 → 8s")
    }

    /// 负数 attempt 返回 0
    func testDelayForNegativeAttempt() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertEqual(policy.delay(forAttempt: -1), 0)
        XCTAssertEqual(policy.delay(forAttempt: -100), 0)
    }

    /// initialDelay=0 时所有 attempt 延迟均为 0
    func testDelayForAttemptWithZeroInitialDelay() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.delay(forAttempt: 0), 0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 0)
        XCTAssertEqual(policy.delay(forAttempt: 2), 0)
    }

    /// 自定义 backoffMultiplier 计算
    func testDelayForAttemptWithCustomMultiplier() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 2.0, backoffMultiplier: 3.0)
        XCTAssertEqual(policy.delay(forAttempt: 0), 2.0, "2 * 3^0 = 2")
        XCTAssertEqual(policy.delay(forAttempt: 1), 6.0, "2 * 3^1 = 6")
        XCTAssertEqual(policy.delay(forAttempt: 2), 18.0, "2 * 3^2 = 18")
    }

    // MARK: - backoffSequence()

    /// 默认策略退避序列：[1, 2]（3 次尝试，2 次重试间隔）
    func testBackoffSequenceWithDefaultPolicy() {
        let policy = RetryPolicy.defaultPolicy
        let sequence = policy.backoffSequence()
        XCTAssertEqual(sequence, [1.0, 2.0])
    }

    /// maxAttempts=1 时退避序列为空（无重试）
    func testBackoffSequenceWithSingleAttempt() {
        let policy = RetryPolicy(maxAttempts: 1, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.backoffSequence(), [], "单次尝试无重试间隔")
    }

    /// maxAttempts=5 时退避序列长度为 4
    func testBackoffSequenceLength() {
        let policy = RetryPolicy(maxAttempts: 5, initialDelay: 1.0, backoffMultiplier: 2.0)
        let sequence = policy.backoffSequence()
        XCTAssertEqual(sequence.count, 4, "5 次尝试 → 4 个重试间隔")
        XCTAssertEqual(sequence, [1.0, 2.0, 4.0, 8.0])
    }

    // MARK: - canRetry(afterAttempt:)

    /// 默认策略：尝试 0/1 次后可重试，尝试 2 次后不可重试
    func testCanRetryWithDefaultPolicy() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertTrue(policy.canRetry(afterAttempt: 0), "首次失败后可重试")
        XCTAssertTrue(policy.canRetry(afterAttempt: 1), "第 2 次失败后可重试")
        XCTAssertFalse(policy.canRetry(afterAttempt: 2), "第 3 次失败后不可重试（已达 maxAttempts）")
        XCTAssertFalse(policy.canRetry(afterAttempt: 3), "超出 maxAttempts 不可重试")
    }

    /// maxAttempts=1 时任何失败都不可重试
    func testCanRetryWithSingleAttempt() {
        let policy = RetryPolicy(maxAttempts: 1, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertFalse(policy.canRetry(afterAttempt: 0), "单次尝试策略不应可重试")
    }

    /// maxAttempts=5 时可重试 4 次
    func testCanRetryWithFiveAttempts() {
        let policy = RetryPolicy(maxAttempts: 5, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertTrue(policy.canRetry(afterAttempt: 0))
        XCTAssertTrue(policy.canRetry(afterAttempt: 1))
        XCTAssertTrue(policy.canRetry(afterAttempt: 2))
        XCTAssertTrue(policy.canRetry(afterAttempt: 3))
        XCTAssertFalse(policy.canRetry(afterAttempt: 4))
    }

    // MARK: - 参数下限保护

    /// maxAttempts < 1 强制为 1
    func testMaxAttemptsLowerBound() {
        let policy = RetryPolicy(maxAttempts: 0, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.maxAttempts, 1, "maxAttempts 应至少为 1")
    }

    /// maxAttempts 负数也强制为 1
    func testMaxAttemptsNegative() {
        let policy = RetryPolicy(maxAttempts: -10, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    /// initialDelay < 0 强制为 0
    func testInitialDelayLowerBound() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: -1.5, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.initialDelay, 0, "initialDelay 应至少为 0")
    }

    /// backoffMultiplier < 1.0 强制为 1.0
    func testBackoffMultiplierLowerBound() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 1.0, backoffMultiplier: 0.5)
        XCTAssertEqual(policy.backoffMultiplier, 1.0, "backoffMultiplier 应至少为 1.0")
    }

    /// backoffMultiplier 负数也强制为 1.0
    func testBackoffMultiplierNegative() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 1.0, backoffMultiplier: -2.0)
        XCTAssertEqual(policy.backoffMultiplier, 1.0)
    }

    // MARK: - 边界值

    /// maxAttempts = 1 时退避序列为空
    func testMaxAttemptsOneEmptyBackoffSequence() {
        let policy = RetryPolicy(maxAttempts: 1, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertTrue(policy.backoffSequence().isEmpty)
    }

    /// delay(forAttempt: 0) 始终等于 initialDelay
    func testDelayForAttemptZeroEqualsInitialDelay() {
        let policies: [RetryPolicy] = [
            RetryPolicy(maxAttempts: 3, initialDelay: 0.5, backoffMultiplier: 2.0),
            RetryPolicy(maxAttempts: 3, initialDelay: 2.0, backoffMultiplier: 1.5),
            RetryPolicy(maxAttempts: 3, initialDelay: 0, backoffMultiplier: 5.0)
        ]
        for policy in policies {
            XCTAssertEqual(policy.delay(forAttempt: 0), policy.initialDelay,
                           "delay(0) 应等于 initialDelay")
        }
    }

    // MARK: - Sendable 合规性

    /// RetryPolicy 应满足 Sendable（可在 actor 间传递）
    func testSendableConformance() {
        let policy = RetryPolicy.defaultPolicy
        // 此测试主要验证编译期 Sendable 合规；运行时无操作
        XCTAssertEqual(policy.maxAttempts, 3)
        // Sendable 类型可在 @Sendable 闭包中捕获
        let closure: @Sendable () -> Int = { policy.maxAttempts }
        XCTAssertEqual(closure(), 3)
    }
}
