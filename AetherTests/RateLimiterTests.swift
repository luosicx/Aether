import XCTest
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
}
