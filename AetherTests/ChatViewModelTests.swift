import XCTest
import SwiftData
import Speech
@testable import Aether

/// ChatViewModel 单元测试（SubTask 17.1 - 17.10）
/// 使用 in-memory SwiftData ModelContainer + 可注入 LLMProvider
@MainActor
final class ChatViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    /// 17.1 表驱动：从尾部累加超过 tokenLimit 时截断（保留最近的、丢弃最早的）
    /// 字符串 estimatedTokens = Int(Double(splitBySpace.count) * 1.3)
    /// "a b" → 2 词 → Int(2.6) = 2 tokens
    func testLimitTokensTruncation() {
        let cases: [(name: String, contents: [String], limit: Int, expectedCount: Int)] = [
            ("全部 fitting", ["a b", "c d", "e f"], 100, 3),   // 2+2+2=6 ≤100，全部保留
            ("超限截断最早一条", ["a b", "c d", "e f", "g h"], 5, 2),  // 反向累加：g h(2)+e f(2)=4 ≤5；再加 c d=6>5 截断 → 保留最近 2 条
            ("空消息列表", [], 10, 0),
            ("tokenLimit=0 立即截断", ["a b"], 0, 0),           // 0+2 > 0 立即 break
            ("单条刚好等于 limit", ["a b"], 2, 1)                // 0+2 ≤2 → 保留 1 条
        ]
        let vm = ChatViewModel()
        for (name, contents, limit, expectedCount) in cases {
            vm.tokenLimit = limit
            let messages = contents.map {
                APIMessage(role: "user", content: $0, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
            }
            let limited = vm.limitTokens(messages, max: limit)
            XCTAssertEqual(limited.count, expectedCount,
                           "用例「\(name)」：期望保留 \(expectedCount) 条，实际 \(limited.count) 条")
        }
    }

    /// 17.2 switchTo 清理所有流式状态并加载目标会话消息
    func testSwitchToClearsState() throws {
        let vm = ChatViewModel()
        // 预置脏状态
        vm.streamingText = "残留流式文本"
        vm.isLoading = true
        vm.currentToolSteps = [ChatViewModel.ToolStep(
            toolName: "calculate", status: .running, result: nil, thought: nil,
            arguments: "{}", loopIndex: 1
        )]
        vm.currentCitations = [DocumentChunk(content: "x")]
        vm.errorMessage = "前次错误"
        vm.inputText = "未发送的输入"

        // 创建目标会话并加 1 条消息
        let conv = Conversation(title: "目标", systemPrompt: "你是助手")
        context.insert(conv)
        let msg = ChatMessage(role: "user", content: "你好")
        msg.conversation = conv
        conv.messages.append(msg)
        try context.save()

        vm.switchTo(conversation: conv)

        XCTAssertEqual(vm.streamingText, "", "streamingText 应被清空")
        XCTAssertFalse(vm.isLoading, "isLoading 应为 false")
        XCTAssertTrue(vm.currentToolSteps.isEmpty, "currentToolSteps 应被清空")
        XCTAssertTrue(vm.currentCitations.isEmpty, "currentCitations 应被清空")
        XCTAssertNil(vm.errorMessage, "errorMessage 应为 nil")
        XCTAssertEqual(vm.inputText, "", "inputText 应被清空")
        XCTAssertEqual(vm.messages.count, 1, "应加载目标会话的 1 条消息")
        XCTAssertEqual(vm.messages.first?.content, "你好")
    }

    /// 17.3 空白输入守卫：sendMessage 不创建消息、不触发 processMessage
    func testSendMessageEmptyInputGuards() throws {
        let vm = ChatViewModel()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        try context.save()

        vm.inputText = "   \n  "  // 纯空白
        vm.sendMessage(in: conv, modelContext: context)

        XCTAssertEqual(conv.messages.count, 0, "空白输入不应创建消息")
        XCTAssertFalse(vm.isLoading, "空白输入不应触发 isLoading")
        XCTAssertNil(vm.errorMessage, "空白输入不应设置 errorMessage")
    }

    /// 17.4 sendMessage 时 pendingImage 应被填充到消息 attachedImage，并清空 pendingImage
    func testSendMessagePendingImageAttachedAndCleared() throws {
        // 注入 MockLLMProvider 避免真实网络调用（其内部 Task 会执行 processMessage）
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        let imageData = Data([0x01, 0x02, 0x03, 0x04])
        vm.pendingImage = imageData
        vm.inputText = "看图"

        vm.sendMessage(in: conv, modelContext: context)

        // 同步断言：用户消息已被 append，且 attachedImage 已填充
        XCTAssertEqual(conv.messages.count, 1, "应创建 1 条用户消息")
        XCTAssertEqual(conv.messages.first?.role, "user")
        XCTAssertEqual(conv.messages.first?.attachedImage, imageData,
                       "pendingImage 应被填充到 attachedImage")
        XCTAssertNil(vm.pendingImage, "发送后 pendingImage 应被清空")
    }

    /// 17.5 preferredTone 非默认时，effectiveSystemPrompt 应注入「【用户偏好】」前缀
    func testProcessMessagePreferenceInjection() {
        let vm = ChatViewModel()
        // 情况 A：非默认 tone → 注入
        let pref = UserPreference()
        pref.preferredTone = "正式"
        let resultA = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(resultA.contains("【用户偏好】"),
                       "非默认 tone 应注入「【用户偏好】」前缀")
        XCTAssertTrue(resultA.contains("语气：正式"),
                       "注入内容应包含「语气：正式」")
        XCTAssertTrue(resultA.hasPrefix("你是助手"),
                       "原 systemPrompt 应作为前缀保留")

        // 情况 B：默认 tone → 不注入
        let prefDefault = UserPreference()
        let resultB = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: prefDefault)
        XCTAssertEqual(resultB, "你是助手",
                       "默认偏好应保持原 systemPrompt 不变")

        // 情况 C：base 为空 + 非默认 tone → 不应出现前缀换行
        let prefEmpty = UserPreference()
        prefEmpty.preferredTone = "轻松"
        let resultC = vm.buildEffectiveSystemPrompt(base: "", preference: prefEmpty)
        XCTAssertTrue(resultC.hasPrefix("【用户偏好】"),
                       "base 为空时「【用户偏好】」应为开头")
    }

    /// 17.6 语义缓存命中走假打字效果：预置缓存命中，调用 processMessage，
    /// 验证 assistant 消息以缓存内容追加、isLoading 复位、streamingText 清空
    func testProcessMessageCacheHitFakeTyping() async throws {
        let embedding: [Float] = [1.0, 0.0, 0.0]
        let mock = MockLLMProvider()
        mock.embedResult = [embedding]  // 与缓存条目同向量 → 余弦相似度 1.0 > 0.92 命中
        let vm = ChatViewModel(client: mock)

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        // 预置缓存命中
        vm.cache.set(query: "你好", embedding: embedding, response: "cached-reply")

        vm.isLoading = true
        await vm.processMessage("你好", conversation: conv, modelContext: context)

        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1, "缓存命中应追加 1 条 assistant 消息")
        XCTAssertEqual(assistantMsgs.first?.content, "cached-reply",
                       "assistant 内容应等于缓存 response")
        XCTAssertFalse(vm.isLoading, "缓存命中后 isLoading 应复位为 false")
        XCTAssertEqual(vm.streamingText, "", "缓存命中后 streamingText 应被清空")
    }

    /// 17.7 识别器不可用时 toggleVoiceInput 应设 errorMessage 且 isRecording 保持 false。
    /// 通过注入 recognizerAvailabilityCheck 返回 false 模拟识别器不可用，
    /// 不再依赖真实 SFSpeechRecognizer 权限状态。
    func testToggleVoiceInputWhenUnavailableSetsError() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "跳过：CI 环境下 SFSpeechRecognizer.requestAuthorization 永不返回")
        let vm = ChatViewModel()
        // 注入：识别器不可用，模拟 startRecording 抛错
        vm.voiceService.recognizerAvailabilityCheck = { false }

        vm.toggleVoiceInput()
        // 轮询等待 errorMessage 被设置（替代固定 Task.sleep）
        let expectation = XCTestExpectation(description: "errorMessage 被设置")
        for _ in 0..<50 {
            if vm.errorMessage != nil {
                expectation.fulfill()
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        await fulfillment(of: [expectation], timeout: 5.0)

        // 权限已授予时走 startRecording 抛错分支（errorMessage 含「录音启动失败」）；
        // 权限未授予时走权限拒绝分支（errorMessage 为「需要语音识别权限」）。
        // 两种情况下都应设置 errorMessage 且 isRecording 保持 false。
        XCTAssertNotNil(vm.errorMessage, "识别器不可用时应设 errorMessage")
        XCTAssertFalse(vm.isRecording, "不可用时 isRecording 应保持 false")
    }

    /// 17.8 同 id 调用 toggleSpeak 第二次应停止朗读并清空 speakingMessageId
    func testToggleSpeakSameIdStops() {
        let vm = ChatViewModel()
        let id = UUID()

        vm.toggleSpeak(messageId: id, content: "hello")
        XCTAssertEqual(vm.speakingMessageId, id,
                       "首次调用应设 speakingMessageId")

        vm.toggleSpeak(messageId: id, content: "hello")
        XCTAssertNil(vm.speakingMessageId,
                     "同 id 第二次调用应停止并清空 speakingMessageId")
    }

    /// 17.9 不同 id 调用 toggleSpeak 应切换 speakingMessageId
    func testToggleSpeakDifferentIdSwitches() {
        let vm = ChatViewModel()
        let id1 = UUID()
        let id2 = UUID()

        vm.toggleSpeak(messageId: id1, content: "hello")
        XCTAssertEqual(vm.speakingMessageId, id1)

        vm.toggleSpeak(messageId: id2, content: "world")
        XCTAssertEqual(vm.speakingMessageId, id2,
                       "切换到不同 id 应更新 speakingMessageId")
    }

    /// 17.x RAG 检索降级守卫：DeepSeek 无 Qwen Key 时 resolveEmbedding 返回 nil
    /// 这是 ChatViewModel RAG 守卫的依赖条件——resolveEmbedding 返回 nil 时，
    /// ragEmbeddingProvider 回退到 selectedProvider（.deepseek），触发守卫跳过 embedding 调用
    func testRAGEmbeddingDegradationDeepSeekNoQwenKey() {
        // 测试环境中 Keychain 无 Qwen Key
        let resolved = EmbeddingService.resolveEmbedding(for: .deepseek)
        XCTAssertNil(resolved, "DeepSeek 无 Qwen Key 时 resolveEmbedding 应返回 nil（触发降级守卫）")

        // Qwen provider 应正常解析（不需要 Qwen Key 降级）
        let qwenResolved = EmbeddingService.resolveEmbedding(for: .qwen)
        XCTAssertNotNil(qwenResolved, "Qwen provider 应正常解析")
        XCTAssertEqual(qwenResolved?.1, .qwen, "Qwen provider 解析结果应为 .qwen")
    }
}

/// 用于单元测试的 LLMProvider 桩实现：chat 返回立即结束的空 stream，embed 返回预设结果
/// 避免在测试中发起真实网络请求
final class MockLLMProvider: LLMProvider {
    /// embed 返回的预设 embedding 二维数组（默认空）
    var embedResult: [[Float]] = []

    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }

    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { $0.finish() }
    }

    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        embedResult
    }
}
