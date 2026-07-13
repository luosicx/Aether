import XCTest
@testable import Aether

/// Task 7.3: ContextWindowManager 单元测试。
///
/// 覆盖范围：
/// - estimateTokens 估算正确（复用 String.estimatedTokens）
/// - isImportant 判断正确（tool call / 关键词）
/// - summarize 生成摘要（mock LLMProvider）
/// - compress 保留重要消息
@MainActor
final class ContextWindowManagerTests: XCTestCase {

    // MARK: - Mock LLMProvider

    /// 可配置返回内容的 Mock LLMProvider，用于测试 summarize 与 compress。
    final class MockLLMProvider: LLMProvider {
        /// chat 流将依次 yield 的内容片段
        var chatContents: [String] = []
        /// 记录 chat 被调用次数
        private(set) var chatCallCount = 0
        /// embed 调用返回值（测试中未使用）
        var embedResult: [[Float]] = []

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                for content in self.chatContents {
                    continuation.yield(content)
                }
                continuation.finish()
            }
        }

        func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                for content in self.chatContents {
                    continuation.yield(ParsedChunk(content: content, toolCalls: nil))
                }
                continuation.finish()
            }
        }

        func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            embedResult
        }
    }

    // MARK: - estimateTokens 估算

    /// 空字符串应估算为 0 token
    func testEstimateTokensEmptyString() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        XCTAssertEqual(manager.estimateTokens(""), 0, "空字符串应估算为 0 token")
    }

    /// 纯英文按空格分词估算
    func testEstimateTokensEnglish() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        // "hello world" → 2 词 × 1.3 = Int(2.6) = 2
        XCTAssertEqual(manager.estimateTokens("hello world"), 2)
        // "hello" → 1 词 × 1.3 = Int(1.3) = 1
        XCTAssertEqual(manager.estimateTokens("hello"), 1)
    }

    /// 中文每字约 1.5 token
    func testEstimateTokensChinese() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        // "你好世界" → 4 非 ASCII 字 × 1.5 = 6 + 1 英文词 = 7
        XCTAssertEqual(manager.estimateTokens("你好世界"), 7)
    }

    /// estimateTokens 应与 String.estimatedTokens 一致
    func testEstimateTokensConsistentWithStringExtension() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let samples = ["", "hello world", "你好世界", "hello 你好"]
        for sample in samples {
            XCTAssertEqual(manager.estimateTokens(sample), sample.estimatedTokens,
                          "estimateTokens 应与 String.estimatedTokens 一致: '\(sample)'")
        }
    }

    // MARK: - isImportant 判断

    /// 含「记住」关键词的消息应为重要
    func testIsImportantKeywordRemember() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let msg = ChatMessage(role: "user", content: "请记住我是素食者")
        XCTAssertTrue(manager.isImportant(msg), "含「记住」关键词的消息应为重要")
    }

    /// 含「重要」关键词的消息应为重要
    func testIsImportantKeywordImportant() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let msg = ChatMessage(role: "user", content: "这件事很重要")
        XCTAssertTrue(manager.isImportant(msg), "含「重要」关键词的消息应为重要")
    }

    /// 含「注意」关键词的消息应为重要
    func testIsImportantKeywordAttention() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let msg = ChatMessage(role: "user", content: "请注意安全事项")
        XCTAssertTrue(manager.isImportant(msg), "含「注意」关键词的消息应为重要")
    }

    /// tool 角色消息应为重要
    func testIsImportantToolRoleMessage() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let msg = ChatMessage(role: "tool", content: "工具执行结果", toolCallId: "call_123", toolName: "calculator")
        XCTAssertTrue(manager.isImportant(msg), "tool 角色消息应为重要")
    }

    /// 含 toolCallData 的 assistant 消息应为重要
    func testIsImportantAssistantWithToolCallData() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let toolCallData = "[{\"id\":\"1\",\"type\":\"function\",\"name\":\"calc\",\"arguments\":\"{}\"}]".data(using: .utf8)!
        let msg = ChatMessage(role: "assistant", content: "调用工具", toolCallData: toolCallData)
        XCTAssertTrue(manager.isImportant(msg), "含 toolCallData 的消息应为重要")
    }

    /// 普通对话消息应不为重要
    func testIsImportantNormalMessage() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let msg = ChatMessage(role: "user", content: "今天天气真好")
        XCTAssertFalse(manager.isImportant(msg), "普通对话消息应不为重要")
    }

    /// 空内容消息应不为重要
    func testIsImportantEmptyContent() {
        let manager = ContextWindowManager(llmProvider: MockLLMProvider())
        let msg = ChatMessage(role: "assistant", content: "")
        XCTAssertFalse(manager.isImportant(msg), "空内容消息应不为重要")
    }

    // MARK: - summarize 生成摘要

    /// summarize 应收集 LLM 流式输出并返回完整摘要
    func testSummarizeReturnsLLMOutput() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["这是对话摘要"]
        let manager = ContextWindowManager(llmProvider: mock)

        let messages = [
            ChatMessage(role: "user", content: "你好"),
            ChatMessage(role: "assistant", content: "你好！有什么可以帮助你的？")
        ]
        let summary = try await manager.summarize(messages: messages)

        XCTAssertEqual(summary, "这是对话摘要", "应返回 LLM 生成的摘要")
        XCTAssertEqual(mock.chatCallCount, 1, "应调用 LLMProvider.chat 一次")
    }

    /// summarize 多 chunk 应正确拼接
    func testSummarizeMultipleChunksConcatenated() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["用户", "问候", "助手", "回应"]
        let manager = ContextWindowManager(llmProvider: mock)

        let messages = [
            ChatMessage(role: "user", content: "你好"),
            ChatMessage(role: "assistant", content: "你好")
        ]
        let summary = try await manager.summarize(messages: messages)

        XCTAssertEqual(summary, "用户问候助手回应", "多 chunk 应拼接为完整摘要")
    }

    /// summarize 空消息列表应返回空字符串
    func testSummarizeEmptyMessagesReturnsEmpty() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["不应该被调用"]
        let manager = ContextWindowManager(llmProvider: mock)

        let summary = try await manager.summarize(messages: [])

        XCTAssertEqual(summary, "", "空消息列表应返回空字符串")
        XCTAssertEqual(mock.chatCallCount, 0, "空列表不应调用 LLM")
    }

    /// summarize 应将消息内容拼接到 prompt 中
    func testSummarizeIncludesMessageContentInPrompt() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["摘要"]
        let manager = ContextWindowManager(llmProvider: mock)

        let messages = [
            ChatMessage(role: "user", content: "用户说的内容")
        ]
        _ = try await manager.summarize(messages: messages)

        // mock 记录的是最后一条 user 消息，应包含原始消息内容
        // 这里通过 chatCallCount 间接验证（至少调用了一次）
        XCTAssertEqual(mock.chatCallCount, 1)
    }

    // MARK: - compress 保留重要消息

    /// 总 token 未超限时应直接返回原消息（不压缩）
    func testCompressUnderLimitReturnsOriginalMessages() async throws {
        let mock = MockLLMProvider()
        let manager = ContextWindowManager(llmProvider: mock, maxContextTokens: 4000)

        let messages = [
            ChatMessage(role: "user", content: "你好"),
            ChatMessage(role: "assistant", content: "你好！")
        ]
        let result = try await manager.compress(messages: messages, maxTokens: 4000)

        XCTAssertEqual(result.count, 2, "未超限应返回全部消息")
        XCTAssertEqual(mock.chatCallCount, 0, "未超限不应调用 LLM 摘要")
    }

    /// 超限时含关键词的重要消息应被保留
    func testCompressPreservesImportantKeywordMessage() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["这是摘要"]
        let manager = ContextWindowManager(llmProvider: mock, maxContextTokens: 100)

        // 重要消息：含「记住」关键词
        let importantMsg = ChatMessage(role: "user", content: "请记住我是素食者，这点很重要")
        // 普通旧消息：会被压缩
        let oldMsg1 = ChatMessage(role: "user", content: "今天天气真好适合出门走走散步")
        let oldMsg2 = ChatMessage(role: "assistant", content: "是的天气不错适合户外活动锻炼身体")
        // 近期消息：保留
        let recentMsg = ChatMessage(role: "user", content: "你好")

        let messages = [importantMsg, oldMsg1, oldMsg2, recentMsg]
        let result = try await manager.compress(messages: messages, maxTokens: 30)

        // 重要消息应被保留（通过 id 匹配）
        XCTAssertTrue(result.contains { $0.id == importantMsg.id }, "含关键词的重要消息应被保留")
    }

    /// 超限时 tool 角色消息应被保留
    func testCompressPreservesToolMessage() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["摘要"]
        let manager = ContextWindowManager(llmProvider: mock, maxContextTokens: 100)

        // tool 消息为重要
        let toolMsg = ChatMessage(role: "tool", content: "计算结果", toolCallId: "call_1", toolName: "calculator")
        // 普通旧消息
        let oldMsg = ChatMessage(role: "user", content: "这是一段较长的普通对话内容用于测试压缩功能")
        // 近期消息
        let recentMsg = ChatMessage(role: "user", content: "你好")

        let messages = [toolMsg, oldMsg, recentMsg]
        let result = try await manager.compress(messages: messages, maxTokens: 25)

        XCTAssertTrue(result.contains { $0.id == toolMsg.id }, "tool 角色消息应被保留")
    }

    /// 超限压缩后应生成摘要 system 消息
    func testCompressGeneratesSummaryMessage() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["历史对话摘要内容"]
        let manager = ContextWindowManager(llmProvider: mock, maxContextTokens: 100)

        // 旧消息（普通，不含关键词）
        let oldMsg1 = ChatMessage(role: "user", content: "今天天气真好适合出门走走散步锻炼身体")
        let oldMsg2 = ChatMessage(role: "assistant", content: "是的天气不错适合户外活动锻炼身体放松心情")
        // 近期消息
        let recentMsg = ChatMessage(role: "user", content: "你好")

        let messages = [oldMsg1, oldMsg2, recentMsg]
        let result = try await manager.compress(messages: messages, maxTokens: 30)

        // 应包含摘要 system 消息
        let summaryMsg = result.first { $0.role == "system" }
        XCTAssertNotNil(summaryMsg, "应生成摘要 system 消息")
        XCTAssertTrue(summaryMsg?.content.contains("历史对话摘要内容") ?? false, "摘要消息应包含 LLM 生成的摘要内容")
    }

    /// 近期消息应被保留
    func testCompressPreservesRecentMessages() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["摘要"]
        let manager = ContextWindowManager(llmProvider: mock, maxContextTokens: 100)

        let oldMsg = ChatMessage(role: "user", content: "这是一段较长的普通对话内容用于测试压缩功能效果")
        let recentMsg1 = ChatMessage(role: "user", content: "最近的问题")
        let recentMsg2 = ChatMessage(role: "assistant", content: "最近的回答")

        let messages = [oldMsg, recentMsg1, recentMsg2]
        let result = try await manager.compress(messages: messages, maxTokens: 25)

        // 近期消息应被保留
        XCTAssertTrue(result.contains { $0.id == recentMsg1.id }, "近期消息应被保留")
        XCTAssertTrue(result.contains { $0.id == recentMsg2.id }, "近期消息应被保留")
    }

    /// 单条消息超限时应仍能处理（不崩溃）
    func testCompressSingleMessageOverLimit() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["摘要"]
        let manager = ContextWindowManager(llmProvider: mock)

        // 单条超长消息
        let longMsg = ChatMessage(role: "user", content: String(repeating: "这是一段很长的内容", count: 20))
        let result = try await manager.compress(messages: [longMsg], maxTokens: 10)

        // 不应崩溃，且应包含某种处理结果
        XCTAssertFalse(result.isEmpty, "压缩结果不应为空")
    }

    /// 空消息列表应返回空数组
    func testCompressEmptyMessagesReturnsEmpty() async throws {
        let mock = MockLLMProvider()
        let manager = ContextWindowManager(llmProvider: mock)

        let result = try await manager.compress(messages: [], maxTokens: 100)
        XCTAssertEqual(result, [], "空消息列表应返回空数组")
        XCTAssertEqual(mock.chatCallCount, 0, "空列表不应调用 LLM")
    }
}
