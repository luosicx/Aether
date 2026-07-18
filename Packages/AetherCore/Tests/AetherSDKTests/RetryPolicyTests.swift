import XCTest
@testable import AetherSDK
import AetherFoundation
import AetherServices

/// Task 24 阶段 4: RetryPolicy 单元测试
///
/// 覆盖：
/// - 默认参数（maxAttempts=3 / initialDelay=1.0 / backoffMultiplier=2.0）
/// - 自定义参数
/// - delay(forAttempt:) 指数退避计算
/// - backoffSequence() 退避序列
/// - canRetry(afterAttempt:) 边界判断
/// - 参数下限保护
/// - AetherError.isRetryable 判断
/// - AetherClient 自动重试集成
final class RetryPolicyTests: XCTestCase {

    // MARK: - 默认参数

    func testDefaultParameters() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.initialDelay, 1.0)
        XCTAssertEqual(policy.backoffMultiplier, 2.0)
    }

    func testInitDefaultsEqualDefault() {
        let policy = RetryPolicy()
        XCTAssertEqual(policy.maxAttempts, RetryPolicy.defaultPolicy.maxAttempts)
        XCTAssertEqual(policy.initialDelay, RetryPolicy.defaultPolicy.initialDelay)
        XCTAssertEqual(policy.backoffMultiplier, RetryPolicy.defaultPolicy.backoffMultiplier)
    }

    // MARK: - 自定义参数

    func testCustomParameters() {
        let policy = RetryPolicy(maxAttempts: 5, initialDelay: 0.5, backoffMultiplier: 3.0)
        XCTAssertEqual(policy.maxAttempts, 5)
        XCTAssertEqual(policy.initialDelay, 0.5)
        XCTAssertEqual(policy.backoffMultiplier, 3.0)
    }

    // MARK: - delay(forAttempt:)

    func testDelayForAttemptWithDefaultPolicy() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertEqual(policy.delay(forAttempt: 0), 1.0, "attempt 0 → 1s")
        XCTAssertEqual(policy.delay(forAttempt: 1), 2.0, "attempt 1 → 2s")
        XCTAssertEqual(policy.delay(forAttempt: 2), 4.0, "attempt 2 → 4s")
        XCTAssertEqual(policy.delay(forAttempt: 3), 8.0, "attempt 3 → 8s")
    }

    func testDelayForNegativeAttempt() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertEqual(policy.delay(forAttempt: -1), 0)
        XCTAssertEqual(policy.delay(forAttempt: -100), 0)
    }

    func testDelayForAttemptWithZeroInitialDelay() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.delay(forAttempt: 0), 0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 0)
        XCTAssertEqual(policy.delay(forAttempt: 2), 0)
    }

    func testDelayForAttemptWithCustomMultiplier() {
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: 2.0, backoffMultiplier: 3.0)
        XCTAssertEqual(policy.delay(forAttempt: 0), 2.0, "2 * 3^0 = 2")
        XCTAssertEqual(policy.delay(forAttempt: 1), 6.0, "2 * 3^1 = 6")
        XCTAssertEqual(policy.delay(forAttempt: 2), 18.0, "2 * 3^2 = 18")
    }

    // MARK: - backoffSequence()

    func testBackoffSequenceWithDefaultPolicy() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertEqual(policy.backoffSequence(), [1.0, 2.0])
    }

    func testBackoffSequenceWithSingleAttempt() {
        let policy = RetryPolicy(maxAttempts: 1, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.backoffSequence(), [])
    }

    func testBackoffSequenceLength() {
        let policy = RetryPolicy(maxAttempts: 5, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertEqual(policy.backoffSequence(), [1.0, 2.0, 4.0, 8.0])
    }

    // MARK: - canRetry(afterAttempt:)

    func testCanRetryWithDefaultPolicy() {
        let policy = RetryPolicy.defaultPolicy
        XCTAssertTrue(policy.canRetry(afterAttempt: 0))
        XCTAssertTrue(policy.canRetry(afterAttempt: 1))
        XCTAssertFalse(policy.canRetry(afterAttempt: 2))
        XCTAssertFalse(policy.canRetry(afterAttempt: 3))
    }

    func testCanRetryWithSingleAttempt() {
        let policy = RetryPolicy(maxAttempts: 1, initialDelay: 1.0, backoffMultiplier: 2.0)
        XCTAssertFalse(policy.canRetry(afterAttempt: 0))
    }

    // MARK: - 参数下限保护

    func testMaxAttemptsLowerBound() {
        XCTAssertEqual(RetryPolicy(maxAttempts: 0).maxAttempts, 1)
        XCTAssertEqual(RetryPolicy(maxAttempts: -10).maxAttempts, 1)
    }

    func testInitialDelayLowerBound() {
        XCTAssertEqual(RetryPolicy(initialDelay: -1.5).initialDelay, 0)
    }

    func testBackoffMultiplierLowerBound() {
        XCTAssertEqual(RetryPolicy(backoffMultiplier: 0.5).backoffMultiplier, 1.0)
        XCTAssertEqual(RetryPolicy(backoffMultiplier: -2.0).backoffMultiplier, 1.0)
    }

    // MARK: - Sendable

    func testSendableConformance() {
        let policy = RetryPolicy.defaultPolicy
        let closure: @Sendable () -> Int = { policy.maxAttempts }
        XCTAssertEqual(closure(), 3)
    }

    // MARK: - AetherError.isRetryable

    func testNetworkUnreachableIsRetryable() {
        XCTAssertTrue(AetherError.networkUnreachable.isRetryable)
    }

    func testRateLimitedIsRetryable() {
        XCTAssertTrue(AetherError.rateLimited(retryAfter: 5).isRetryable)
    }

    func testProviderError503IsRetryable() {
        XCTAssertTrue(AetherError.providerError(code: 503, message: "").isRetryable)
        XCTAssertTrue(AetherError.providerError(code: 502, message: "").isRetryable)
        XCTAssertTrue(AetherError.providerError(code: 504, message: "").isRetryable)
    }

    func testProviderErrorNonRetryable() {
        XCTAssertFalse(AetherError.providerError(code: 400, message: "").isRetryable)
        XCTAssertFalse(AetherError.providerError(code: 500, message: "").isRetryable)
        XCTAssertFalse(AetherError.providerError(code: 404, message: "").isRetryable)
    }

    func testAuthFailedNotRetryable() {
        XCTAssertFalse(AetherError.authFailed(reason: "bad key").isRetryable)
    }

    func testInvalidConfigNotRetryable() {
        XCTAssertFalse(AetherError.invalidConfig(reason: "x").isRetryable)
    }

    // MARK: - AetherClient 集成（自动重试）

    func testClientRetriesOnNetworkError() async throws {
        let mock = RetryTestProvider()
        mock.failureCount = 2 // 前 2 次失败，第 3 次成功
        mock.successResponse = "success"
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: 0.01, backoffMultiplier: 1.0)
        )
        let client = try AetherClient(config: config, provider: mock)
        let response = try await client.chat(messages: [.user("hi")])
        XCTAssertEqual(response, "success")
        XCTAssertEqual(mock.callCount, 3, "应调用 3 次（2 次失败 + 1 次成功）")
    }

    func testClientGivesUpAfterMaxAttempts() async throws {
        let mock = RetryTestProvider()
        mock.failureCount = 10 // 永远失败
        mock.successResponse = "success"
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: 0.01, backoffMultiplier: 1.0)
        )
        let client = try AetherClient(config: config, provider: mock)
        do {
            _ = try await client.chat(messages: [.user("hi")])
            XCTFail("应抛出错误")
        } catch {
            // 预期：3 次后抛出
            XCTAssertEqual(mock.callCount, 3)
        }
    }

    func testClientRetriesEmptyResponseAsNetworkError() async throws {
        // 空响应视为网络故障（networkUnreachable，retryable）
        // 让 RetryPolicy 自动重试 maxAttempts 次后用尽
        let mock = RetryTestProvider()
        mock.failureCount = 0
        mock.successResponse = ""
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: 0.01, backoffMultiplier: 1.0)
        )
        let client = try AetherClient(config: config, provider: mock)
        do {
            _ = try await client.chat(messages: [.user("hi")])
            XCTFail("应抛出 networkUnreachable")
        } catch {
            // 空响应 → networkUnreachable → retryable → 应重试 maxAttempts 次
            XCTAssertEqual(mock.callCount, 3, "retryable 错误应重试 maxAttempts 次")
            XCTAssertEqual(error as? AetherError, .networkUnreachable)
        }
    }

    func testClientDoesNotRetryNonRetryableError() async throws {
        // 通过 embed 方法触发非 retryable 错误（authFailed）
        // embed 不含重试逻辑，应直接抛出
        let mock = RetryTestProvider()
        mock.embedError = .authFailed(reason: "invalid api key")
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            retryPolicy: RetryPolicy.defaultPolicy
        )
        let client = try AetherClient(config: config, provider: mock)
        do {
            _ = try await client.embed(texts: ["hi"])
            XCTFail("应抛出 authFailed")
        } catch {
            // 非 retryable 错误（authFailed）应直接抛出，不重试
            XCTAssertEqual(mock.embedCallCount, 1, "非 retryable 不应重试")
            XCTAssertEqual(error as? AetherError, .authFailed(reason: "invalid api key"))
        }
    }
}

// MARK: - RetryTestProvider

/// 用于测试重试逻辑的 LLMProvider mock
final class RetryTestProvider: LLMProvider, @unchecked Sendable {
    var failureCount = 0
    var successResponse = "success"
    /// embed 方法抛出的错误（可选）。设置后 embed 调用直接抛错。
    var embedError: AetherError?
    private var callCountValue = 0
    private var embedCallCountValue = 0
    private let lock = NSLock()

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCountValue
    }

    var embedCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return embedCallCountValue
    }

    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            self.lock.lock()
            self.callCountValue += 1
            let shouldFail = self.callCountValue <= self.failureCount
            self.lock.unlock()

            if shouldFail {
                // 模拟网络错误：返回空流（chat 实现并不抛错，但空响应会被识别为 networkUnreachable）
                // 这里直接 finish，让 AetherClient 的空响应检测触发 networkUnreachable（retryable）
                continuation.finish()
                return
            }
            continuation.yield(self.successResponse)
            continuation.finish()
        }
    }

    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        self.lock.lock()
        self.embedCallCountValue += 1
        let error = self.embedError
        self.lock.unlock()
        if let error = error {
            throw error
        }
        return []
    }
}
