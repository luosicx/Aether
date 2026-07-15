import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Day 15 Phase 5 Task 12: RateLimiter 单元测试
/// 验证令牌桶限流器的 chat/embed 独立计数、耗尽抛 LLMError.rateLimited、以及自定义限额。
final class RateLimiterTests: XCTestCase {

    /// 辅助：断言 acquireChat 抛 LLMError.rateLimited(retryAfter: 60)
    private func assertChatRateLimited(_ limiter: RateLimiter, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await limiter.acquireChat()
            XCTFail("应抛 rateLimited", file: file, line: line)
        } catch let error as LLMError {
            guard case .rateLimited(let retryAfter) = error else {
                XCTFail("期望 .rateLimited，实际：\(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(retryAfter, 60, "retryAfter 应为 60 秒", file: file, line: line)
        } catch {
            XCTFail("期望 LLMError，实际：\(type(of: error))", file: file, line: line)
        }
    }

    /// 辅助：断言 acquireEmbed 抛 LLMError.rateLimited
    private func assertEmbedRateLimited(_ limiter: RateLimiter, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await limiter.acquireEmbed()
            XCTFail("应抛 rateLimited", file: file, line: line)
        } catch let error as LLMError {
            guard case .rateLimited = error else {
                XCTFail("期望 .rateLimited，实际：\(error)", file: file, line: line)
                return
            }
        } catch {
            XCTFail("期望 LLMError，实际：\(type(of: error))", file: file, line: line)
        }
    }

    // MARK: - 1. acquireChat 消耗令牌：chatPerMin=5，前 5 次成功，第 6 次抛 rateLimited

    func testAcquireChatConsumesToken() async throws {
        let limiter = RateLimiter(chatPerMin: 5, embedPerMin: 10)
        // 先消耗 1 个
        try await limiter.acquireChat()
        // 再消耗 4 个（共 5 个，应全部成功）
        for _ in 0..<4 {
            try await limiter.acquireChat()
        }
        // 第 6 次应抛 rateLimited
        await assertChatRateLimited(limiter)
    }

    // MARK: - 2. acquireChat 超限抛 rateLimited：chatPerMin=2，第 3 次抛 rateLimited(retryAfter: 60)

    func testAcquireChatExceedingLimitThrowsRateLimited() async throws {
        let limiter = RateLimiter(chatPerMin: 2, embedPerMin: 10)
        try await limiter.acquireChat()
        try await limiter.acquireChat()
        await assertChatRateLimited(limiter)
    }

    // MARK: - 3. acquireEmbed 与 acquireChat 独立：chat 耗尽后 embed 仍可用

    func testAcquireEmbedIndependentFromChat() async throws {
        let limiter = RateLimiter(chatPerMin: 1, embedPerMin: 5)
        // 消耗唯一的 chat 令牌
        try await limiter.acquireChat()
        // chat 应被限流
        await assertChatRateLimited(limiter)
        // embed 仍可成功 5 次
        for _ in 0..<5 {
            try await limiter.acquireEmbed()
        }
        // 第 6 次 embed 应抛 rateLimited
        await assertEmbedRateLimited(limiter)
    }

    // MARK: - 4. 耗尽后立即 acquire 抛 rateLimited（refill 需 60 秒，此处不等待）

    func testRefillAfter60Seconds() async throws {
        let limiter = RateLimiter(chatPerMin: 2, embedPerMin: 10)
        try await limiter.acquireChat()
        try await limiter.acquireChat()
        // 耗尽后立即再 acquire 应抛 rateLimited（距上次填充不足 60 秒）
        await assertChatRateLimited(limiter)
    }

    // MARK: - 5. 自定义限流：chatPerMin=5，5 次成功，第 6 次抛错

    func testCustomRateLimit() async throws {
        let limiter = RateLimiter(chatPerMin: 5, embedPerMin: 10)
        for _ in 0..<5 {
            try await limiter.acquireChat()
        }
        await assertChatRateLimited(limiter)
    }

    // MARK: - 边缘测试补充

    // 默认初始化：chatPerMin=20，embedPerMin=10，应分别允许 20/10 次成功
    func testDefaultInitValues() async throws {
        let limiter = RateLimiter() // 使用默认值 chatPerMin=20, embedPerMin=10
        // chat 应可成功 20 次
        for _ in 0..<20 {
            try await limiter.acquireChat()
        }
        await assertChatRateLimited(limiter)
        // embed 应可成功 10 次
        for _ in 0..<10 {
            try await limiter.acquireEmbed()
        }
        await assertEmbedRateLimited(limiter)
    }

    // embed 耗尽后 chat 仍可用：验证两类令牌独立计数
    func testEmbedExhaustedChatStillAvailable() async throws {
        let limiter = RateLimiter(chatPerMin: 3, embedPerMin: 1)
        // 耗尽唯一的 embed 令牌
        try await limiter.acquireEmbed()
        await assertEmbedRateLimited(limiter)
        // chat 仍可使用 3 次
        for _ in 0..<3 {
            try await limiter.acquireChat()
        }
        await assertChatRateLimited(limiter)
    }

    // 交错申请 chat 与 embed：互不影响各自计数
    func testInterleavedChatAndEmbed() async throws {
        let limiter = RateLimiter(chatPerMin: 2, embedPerMin: 2)
        try await limiter.acquireChat()
        try await limiter.acquireEmbed()
        try await limiter.acquireChat()
        try await limiter.acquireEmbed()
        // 两者均已耗尽
        await assertChatRateLimited(limiter)
        await assertEmbedRateLimited(limiter)
    }

    // 边界条件：chatPerMin=1，仅一次成功，第二次即限流
    func testSingleChatTokenSucceedsOnce() async throws {
        let limiter = RateLimiter(chatPerMin: 1, embedPerMin: 5)
        try await limiter.acquireChat()
        await assertChatRateLimited(limiter)
    }

    // MARK: - 补充边界测试

    /// 令牌耗尽后立即再申请应被限流（距上次补充不足 60 秒）
    func testImmediateReacquireAfterExhaustionIsBlocked() async throws {
        let limiter = RateLimiter(chatPerMin: 3, embedPerMin: 3)
        // 耗尽所有 chat 令牌
        for _ in 0..<3 {
            try await limiter.acquireChat()
        }
        // 立即再申请应被限流
        await assertChatRateLimited(limiter)
        // 同理耗尽 embed
        for _ in 0..<3 {
            try await limiter.acquireEmbed()
        }
        await assertEmbedRateLimited(limiter)
    }

    /// 默认限额 chatPerMin=20 的精确验证：前 20 次成功，第 21 次限流
    func testDefaultChatLimitExactBoundary() async throws {
        let limiter = RateLimiter()
        for i in 0..<20 {
            do {
                try await limiter.acquireChat()
            } catch {
                XCTFail("第 \(i+1) 次 acquireChat 不应失败: \(error)")
            }
        }
        await assertChatRateLimited(limiter)
    }

    /// 默认限额 embedPerMin=10 的精确验证：前 10 次成功，第 11 次限流
    func testDefaultEmbedLimitExactBoundary() async throws {
        let limiter = RateLimiter()
        for i in 0..<10 {
            do {
                try await limiter.acquireEmbed()
            } catch {
                XCTFail("第 \(i+1) 次 acquireEmbed 不应失败: \(error)")
            }
        }
        await assertEmbedRateLimited(limiter)
    }

    /// chatPerMin=0 时任何 chat 申请应立即限流
    func testZeroChatLimitImmediatelyBlocks() async {
        let limiter = RateLimiter(chatPerMin: 0, embedPerMin: 5)
        await assertChatRateLimited(limiter)
    }

    /// embedPerMin=0 时任何 embed 申请应立即限流
    func testZeroEmbedLimitImmediatelyBlocks() async {
        let limiter = RateLimiter(chatPerMin: 5, embedPerMin: 0)
        await assertEmbedRateLimited(limiter)
    }

    /// chat 和 embed 同时耗尽后两者均应被限流
    func testBothExhaustedSimultaneously() async throws {
        let limiter = RateLimiter(chatPerMin: 1, embedPerMin: 1)
        try await limiter.acquireChat()
        try await limiter.acquireEmbed()
        await assertChatRateLimited(limiter)
        await assertEmbedRateLimited(limiter)
    }

    /// 多次连续限流错误类型一致性：始终抛 LLMError.rateLimited(retryAfter: 60)
    func testRepeatedRateLimitErrorsAreConsistent() async throws {
        let limiter = RateLimiter(chatPerMin: 1, embedPerMin: 10)
        try await limiter.acquireChat()
        // 连续 3 次应抛相同类型的错误
        for _ in 0..<3 {
            await assertChatRateLimited(limiter)
        }
    }

    // MARK: - 补充小缺口测试（60 秒令牌补充）

    /// 验证 refillIfNeeded() 的 elapsed >= 60 分支：令牌耗尽后等待 61 秒，
    /// 再次 acquireChat 应成功（chatTokens 被重置到 chatPerMin 上限）。
    /// 覆盖 RateLimiter.swift 第 48-52 行的 elapsed >= 60 分支。
    /// 注意：测试耗时约 61 秒，仅本地运行；CI 中跳过（maximum-test-execution-time-allowance 60s 限制）。
    func testRefillAfter60SecondsResetsTokens() async throws {
        // CI 环境跳过：61 秒等待超过 CI 的 maximum-test-execution-time-allowance(60s)
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                     "CI 环境跳过 61 秒等待测试（超过 maximum-test-execution-time-allowance）")
        // 请求额外的执行时间（默认 60 秒不够等待 61 秒的 refill）
        executionTimeAllowance = 90
        // 在测试方法内创建 limiter，避免 setUp/tearDown 的状态污染
        let limiter = RateLimiter(chatPerMin: 2, embedPerMin: 10)
        // 耗尽所有 chat 令牌
        try await limiter.acquireChat()
        try await limiter.acquireChat()
        // 立即再申请应被限流（距上次补充不足 60 秒）
        await assertChatRateLimited(limiter)

        // 等待 61 秒，使 refillIfNeeded 的 elapsed >= 60 分支被触发
        let expectation = XCTestExpectation(description: "等待 61 秒后令牌被重置")
        let queue = DispatchQueue.global()
        queue.asyncAfter(deadline: .now() + 61) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 70.0)

        // 61 秒后再次 acquireChat 应成功（令牌已被重置）
        do {
            try await limiter.acquireChat()
        } catch {
            XCTFail("等待 61 秒后 acquireChat 应成功，但抛出错误：\(error)")
        }
    }

    /// 验证 refillIfNeeded() 在 60 秒后同时重置 chat 与 embed 两类令牌。
    /// 覆盖 RateLimiter.swift 第 48-52 行的 elapsed >= 60 分支中 chatTokens 与 embedTokens 同时重置。
    /// 注意：测试耗时约 61 秒，仅本地运行；CI 中跳过（maximum-test-execution-time-allowance 60s 限制）。
    func testRefillResetsBothChatAndEmbedTokens() async throws {
        // CI 环境跳过：61 秒等待超过 CI 的 maximum-test-execution-time-allowance(60s)
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                     "CI 环境跳过 61 秒等待测试（超过 maximum-test-execution-time-allowance）")
        // 请求额外的执行时间（默认 60 秒不够等待 61 秒的 refill）
        executionTimeAllowance = 90
        let limiter = RateLimiter(chatPerMin: 1, embedPerMin: 1)
        // 耗尽两类令牌
        try await limiter.acquireChat()
        try await limiter.acquireEmbed()
        // 两类均应被限流
        await assertChatRateLimited(limiter)
        await assertEmbedRateLimited(limiter)

        // 等待 61 秒，触发 refillIfNeeded 的 elapsed >= 60 分支
        let expectation = XCTestExpectation(description: "等待 61 秒后 chat 与 embed 令牌均被重置")
        let queue = DispatchQueue.global()
        queue.asyncAfter(deadline: .now() + 61) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 70.0)

        // 61 秒后两类令牌均应被重置到初始上限
        do {
            try await limiter.acquireChat()
        } catch {
            XCTFail("等待 61 秒后 acquireChat 应成功，但抛出错误：\(error)")
        }
        do {
            try await limiter.acquireEmbed()
        } catch {
            XCTFail("等待 61 秒后 acquireEmbed 应成功，但抛出错误：\(error)")
        }
    }
}
