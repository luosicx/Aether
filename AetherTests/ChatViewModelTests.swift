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
        // 隔离 Keychain：使用内存后端，避免依赖真实系统 Keychain（各测试可自行 saveAPIKey 预置 key）
        KeychainManager.shared.backend = InMemoryKeychainBackend()
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        // 恢复真实 Keychain 后端，避免影响其他测试类
        KeychainManager.shared.backend = SystemKeychainBackend()
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
        XCTAssertTrue(resultA.contains(String(format: NSLocalizedString("语气：%@", comment: ""), "正式")),
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
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil, "跳过：模拟器环境下 SFSpeechRecognizer.requestAuthorization 永不返回")
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

    // MARK: - 深度补充测试

    /// 17.10 processMessage 桩回复模式（UITEST_DISABLE_NETWORK）：
    /// 以 UITEST_DISABLE_NETWORK 启动参数运行时，processMessage 应短路为固定桩回复，
    /// 追加 assistant 消息并清理流式状态。无此启动参数时跳过（需 UITEST scheme 配合）。
    func testProcessMessageStubReplyUITESTMode() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_NETWORK"),
            "需以 -UITEST_DISABLE_NETWORK 启动参数运行"
        )
        let vm = ChatViewModel()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("桩测试内容", conversation: conv, modelContext: context)

        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1, "桩模式应追加 1 条 assistant 消息")
        XCTAssertTrue(assistantMsgs.first?.content.contains("桩测试内容") == true,
                      "桩回复应包含原始输入文本")
        XCTAssertFalse(vm.isLoading, "桩模式完成后 isLoading 应为 false")
        XCTAssertEqual(vm.streamingText, "", "桩模式完成后 streamingText 应被清空")
    }

    /// 17.11 sendMessage 非空输入流程：追加用户消息、清空 inputText、翻转 isLoading，
    /// 后台 processMessage 完成后 isLoading 复位并追加 assistant 消息。
    func testSendMessageFlowAppendsAndTogglesLoading() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["你好", "，世界"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice  // 端侧推理绕过 apiKey 检查
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.inputText = "测试消息"
        vm.sendMessage(in: conv, modelContext: context)

        // 同步断言：sendMessage 立即设置的状态
        XCTAssertTrue(vm.isLoading, "sendMessage 后 isLoading 应为 true")
        XCTAssertEqual(vm.inputText, "", "inputText 应被清空")
        XCTAssertEqual(conv.messages.count, 1, "应追加 1 条用户消息")
        XCTAssertEqual(conv.messages.first?.role, "user")
        XCTAssertEqual(conv.messages.first?.content, "测试消息")
        XCTAssertEqual(vm.streamingText, "", "streamingText 应被重置")
        XCTAssertTrue(vm.currentToolSteps.isEmpty, "currentToolSteps 应被清空")

        // 轮询等待后台 processMessage Task 完成（streamingTask 为 private，无法直接 await）
        for _ in 0..<100 {
            if !vm.isLoading { break }
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        XCTAssertFalse(vm.isLoading, "processMessage 完成后 isLoading 应为 false")
        XCTAssertEqual(vm.streamingText, "", "streamingText 应被清空")
        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1, "应追加 1 条 assistant 消息")
        XCTAssertEqual(assistantMsgs.first?.content, "你好，世界",
                       "assistant 内容应为所有 chunk 拼接")
    }

    /// 17.12 RAG 开启 + DeepSeek provider（无 Qwen Key）：
    /// ragEmbeddingProvider 降级到 .deepseek，应设置 embedding 不支持错误并清空 citations。
    /// 预置 DeepSeek API Key 以绕过 apiKey 缺失检查（否则 RAG 错误会被覆盖）。
    func testProcessMessageRAGEnabledDeepSeekSetsEmbeddingError() async throws {
        try KeychainManager.shared.saveAPIKey("test-key", for: .deepseek)

        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        vm.ragEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(
            vm.errorMessage,
            NSLocalizedString("DeepSeek 不支持知识库嵌入，请在设置中配置 Qwen API Key 或切换供应商为 Qwen", comment: ""),
            "RAG + DeepSeek 无 Qwen Key 时应设置 embedding 不支持错误"
        )
        XCTAssertTrue(vm.currentCitations.isEmpty, "RAG 降级时应清空 currentCitations")
    }

    /// 17.13 RAG 关闭：currentCitations 应被清空（即使预置了非空值）
    func testProcessMessageRAGDisabledClearsCitations() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.ragEnabled = false
        // 预置非空 citations，验证 processMessage 会清空
        vm.currentCitations = [DocumentChunk(content: "旧引用1"), DocumentChunk(content: "旧引用2")]
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertTrue(vm.currentCitations.isEmpty, "RAG 关闭时 currentCitations 应被清空")
    }

    /// 17.14 工具调用开启：mock 返回 toolCalls，验证 currentToolSteps 更新（status=.completed，result 正确）
    func testProcessMessageToolsEnabledUpdatesToolSteps() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "call-1", type: "function", name: "calculate",
                arguments: "{\"expression\": \"1 + 2\"}"
            )
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算 1+2")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算 1+2", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1, "应创建 1 个 ToolStep")
        let step = vm.currentToolSteps[0]
        XCTAssertEqual(step.toolName, "calculate")
        XCTAssertEqual(step.status, .completed, "calculate 执行成功时 status 应为 .completed")
        XCTAssertEqual(step.result, "3", "calculate 1+2 结果应为 3")
        XCTAssertEqual(step.loopIndex, 1, "首轮 loopIndex 应为 1")
        // 验证 tool 消息被追加到 conversation
        let toolMsgs = conv.messages.filter { $0.role == "tool" }
        XCTAssertEqual(toolMsgs.count, 1, "应追加 1 条 tool 消息")
        XCTAssertEqual(toolMsgs.first?.toolName, "calculate")
        XCTAssertEqual(toolMsgs.first?.toolCallId, "call-1")
    }

    /// 17.15 工具调用关闭：不应产生 ToolStep，走纯文本 chat 路径
    func testProcessMessageToolsDisabledNoToolSteps() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["普通回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = false
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertTrue(vm.currentToolSteps.isEmpty, "工具关闭时不应产生 ToolStep")
        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1)
        XCTAssertEqual(assistantMsgs.first?.content, "普通回复")
    }

    /// 17.16 模型选择 auto 模式 + 短文本：SmartRouter 路由到 deepseek-chat
    func testProcessMessageModelSelectionAutoRoutesToChat() async throws {
        try KeychainManager.shared.saveAPIKey("test-key", for: .deepseek)
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        vm.modelSelectionMode = "auto"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(mock.capturedConfig?.model, "deepseek-chat",
                       "auto 模式短文本应路由到 deepseek-chat")
    }

    /// 17.17 模型选择 auto 模式 + 长文本(>=50字)：SmartRouter 路由到 deepseek-reasoner
    func testProcessMessageModelSelectionAutoRoutesToReasoner() async throws {
        try KeychainManager.shared.saveAPIKey("test-key", for: .deepseek)
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        vm.modelSelectionMode = "auto"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let longText = String(repeating: "这是一段需要深度推理的长文本。", count: 5)  // 75 字符 >= 50
        let userMsg = ChatMessage(role: "user", content: longText)
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage(longText, conversation: conv, modelContext: context)

        XCTAssertEqual(mock.capturedConfig?.model, "deepseek-reasoner",
                       "auto 模式长文本(>=50字)应路由到 deepseek-reasoner")
    }

    /// 17.18 模型选择手动 chat 模式：modelSelectionMode = "deepseek-chat"
    func testProcessMessageModelSelectionChatMode() async throws {
        try KeychainManager.shared.saveAPIKey("test-key", for: .deepseek)
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        vm.modelSelectionMode = "deepseek-chat"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(mock.capturedConfig?.model, "deepseek-chat",
                       "手动 chat 模式应映射到 deepseek-chat")
    }

    /// 17.19 模型选择手动 reasoner 模式：modelSelectionMode = "deepseek-reasoner"
    func testProcessMessageModelSelectionReasonerMode() async throws {
        try KeychainManager.shared.saveAPIKey("test-key", for: .deepseek)
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        vm.modelSelectionMode = "deepseek-reasoner"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(mock.capturedConfig?.model, "deepseek-reasoner",
                       "手动 reasoner 模式应映射到 deepseek-reasoner")
    }

    /// 17.20 streamingText 累积和清理：多 chunk 拼接后 streamingText 清空，assistant 内容为完整拼接
    func testProcessMessageStreamingAccumulationAndCleanup() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["Hello", " ", "World", "!"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "hi")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("hi", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.streamingText, "", "processMessage 完成后 streamingText 应被清空")
        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1)
        XCTAssertEqual(assistantMsgs.first?.content, "Hello World!",
                       "assistant 内容应为所有 chunk 拼接结果")
    }

    /// 17.21 错误处理：apiKey 缺失时设置 errorMessage 并复位 isLoading
    func testProcessMessageErrorMessageWhenAPIKeyMissing() async throws {
        // InMemoryKeychainBackend 默认无 key → apiKey 为空
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.errorMessage, LLMError.apiKeyMissing.userMessage,
                       "apiKey 缺失时应设置 apiKeyMissing 错误消息")
        XCTAssertFalse(vm.isLoading, "错误后 isLoading 应为 false")
        XCTAssertEqual(vm.streamingText, "", "错误后 streamingText 应被清空")
    }

    /// 17.22 conversation 消息追加：processMessage 完成后 assistant 消息追加到 conversation
    func testProcessMessageAppendsAssistantMessageToConversation() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["这是回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)
        let initialCount = conv.messages.count

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(conv.messages.count, initialCount + 1, "应追加 1 条 assistant 消息")
        // SwiftData 双向关系可能导致 conversation.messages 顺序不确定，
        // 用 vm.messages（普通数组）验证追加的 assistant 消息
        let assistantMsgs = vm.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1, "vm.messages 应含 1 条 assistant 消息")
        XCTAssertEqual(assistantMsgs.first?.content, "这是回复")
        // vm.messages 也应同步更新
        XCTAssertTrue(vm.messages.contains(where: { $0.role == "assistant" && $0.content == "这是回复" }),
                       "vm.messages 也应包含该 assistant 消息")
    }

    /// 17.23 工具执行失败：currentToolSteps 标记 .failed 并设置 errorMessage
    func testProcessMessageToolExecutionFailureSetsFailedStatus() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "call-fail", type: "function",
                name: "nonexistent_tool", arguments: "{}"
            )
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "调用不存在工具")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("调用不存在工具", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1, "应创建 1 个 ToolStep")
        let step = vm.currentToolSteps[0]
        XCTAssertEqual(step.toolName, "nonexistent_tool")
        XCTAssertEqual(step.status, .failed, "工具未注册时 status 应为 .failed")
        XCTAssertNotNil(step.result, "失败时应记录错误结果")
        XCTAssertNotNil(vm.errorMessage, "工具失败时应设置 errorMessage")
        XCTAssertTrue(vm.errorMessage?.contains("nonexistent_tool") == true,
                     "errorMessage 应包含工具名")
    }

    // MARK: - 深度补充测试 Phase 2：BFF / Fallback / OnDevice / 状态清理 / 错误分支

    /// BFF 模式启用时跳过 apiKey 缺失检查（BFF 分支优先于 apiKey 守卫）
    func testBFFModeSkipsAPIKeyMissingCheck() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["BFF 回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        vm.bffConfig.enabled = true
        // 不保存 apiKey（InMemoryKeychainBackend 默认空）

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertNil(vm.errorMessage, "BFF 模式启用时应跳过 apiKey 缺失检查，不设 errorMessage")
        XCTAssertFalse(vm.isLoading, "完成后 isLoading 应为 false")
        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1, "应追加 1 条 assistant 消息")
        XCTAssertEqual(assistantMsgs.first?.content, "BFF 回复")
    }

    /// BFF 模式令牌桶耗尽后抛 rateLimited，errorMessage 设为限流提示
    func testBFFModeRateLimitExhaustionSetsErrorMessage() async throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice  // 跳过 apiKey 检查，仅依赖 BFF 限流器
        vm.bffConfig.enabled = true
        // chatRateLimitPerMin 默认 20，消耗 20 次后第 21 次应触发限流
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        for i in 0..<20 {
            vm.errorMessage = nil
            await vm.processMessage("你好", conversation: conv, modelContext: context)
            XCTAssertNil(vm.errorMessage, "第 \(i + 1) 次调用不应触发限流")
        }
        // 第 21 次应触发限流
        await vm.processMessage("你好", conversation: conv, modelContext: context)
        XCTAssertEqual(
            vm.errorMessage,
            String(format: NSLocalizedString("请求过于频繁，请 %d 秒后重试", comment: ""), 60),
            "令牌耗尽后应设置限流 errorMessage"
        )
        XCTAssertFalse(vm.isLoading, "限流后 isLoading 应为 false")
    }

    /// FallbackLLMProvider 主 provider 无产出时降级到备用 provider
    func testFallbackProviderTriggersFallbackWhenPrimaryEmpty() async throws {
        let primaryMock = MockLLMProvider()
        primaryMock.chatChunks = []  // 主 provider 无产出 → 触发降级
        let fallbackMock = MockLLMProvider()
        fallbackMock.chatChunks = ["降级", "回复"]
        let fallbackClient = FallbackLLMProvider(
            primary: primaryMock, fallback: fallbackMock,
            primaryProvider: .deepseek, fallbackProvider: .qwen
        )
        let vm = ChatViewModel(client: fallbackClient)
        vm.selectedProvider = .onDevice  // 跳过 apiKey 检查

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.lastUsedProvider, .qwen, "主 provider 无产出时 lastUsedProvider 应为备用 .qwen")
        XCTAssertTrue(vm.didFallbackLastRequest, "应标记 didFallbackLastRequest = true")
        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1)
        XCTAssertEqual(assistantMsgs.first?.content, "降级回复", "应使用备用 provider 的内容")
    }

    /// FallbackLLMProvider 主 provider 有产出时不降级
    func testFallbackProviderNoFallbackWhenPrimaryYields() async throws {
        let primaryMock = MockLLMProvider()
        primaryMock.chatChunks = ["主回复"]
        let fallbackMock = MockLLMProvider()
        fallbackMock.chatChunks = ["不应使用"]
        let fallbackClient = FallbackLLMProvider(
            primary: primaryMock, fallback: fallbackMock,
            primaryProvider: .deepseek, fallbackProvider: .qwen
        )
        let vm = ChatViewModel(client: fallbackClient)
        vm.selectedProvider = .onDevice

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.lastUsedProvider, .deepseek, "主 provider 有产出时 lastUsedProvider 应为主 .deepseek")
        XCTAssertFalse(vm.didFallbackLastRequest, "不应触发降级")
        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.first?.content, "主回复", "应使用主 provider 的内容")
    }

    /// 非 Fallback 路径：普通 MockLLMProvider 时 lastUsedProvider 初值为 effectiveProvider
    func testLastUsedProviderInitializedToSelectedProvider() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice  // toolsEnabled=false → effectiveProvider=selectedProvider

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.lastUsedProvider, .onDevice, "非降级时 lastUsedProvider 应为 selectedProvider")
        XCTAssertFalse(vm.didFallbackLastRequest)
    }

    /// switchToOnDevice 保存原 provider 并切换到端侧；switchToOriginalProvider 恢复
    func testSwitchToOnDeviceAndOriginalProviderRoundTrip() {
        let vm = ChatViewModel()
        vm.selectedProvider = .deepseek

        vm.switchToOnDevice()
        XCTAssertEqual(vm.selectedProvider, .onDevice, "switchToOnDevice 后 selectedProvider 应为 .onDevice")

        vm.switchToOriginalProvider()
        XCTAssertEqual(vm.selectedProvider, .deepseek, "switchToOriginalProvider 后应恢复为 .deepseek")
    }

    /// switchToOnDevice 守卫：已处于 onDevice 时不重复保存原 provider
    func testSwitchToOnDeviceGuardWhenAlreadyOnDevice() {
        let vm = ChatViewModel()
        vm.selectedProvider = .onDevice  // 已是 onDevice

        vm.switchToOnDevice()  // 守卫应直接 return，不保存原 provider
        XCTAssertEqual(vm.selectedProvider, .onDevice)

        // 此时无 originalSelectedProvider，switchToOriginalProvider 应无操作
        vm.switchToOriginalProvider()
        XCTAssertEqual(vm.selectedProvider, .onDevice, "无保存的原 provider 时应保持 .onDevice")
    }

    /// switchToOriginalProvider 守卫：非 onDevice 状态时不恢复
    func testSwitchToOriginalProviderGuardWhenNotOnDevice() {
        let vm = ChatViewModel()
        vm.selectedProvider = .qwen

        vm.switchToOriginalProvider()  // 非 onDevice，守卫应直接 return
        XCTAssertEqual(vm.selectedProvider, .qwen, "非 onDevice 时 switchToOriginalProvider 应无操作")
    }

    /// onDevice provider 跳过 apiKey 检查（无 apiKey 也能正常请求）
    func testOnDeviceProviderSkipsAPIKeyCheck() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["端侧回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        // 不保存 apiKey

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertNil(vm.errorMessage, "onDevice 应跳过 apiKey 检查，不设 errorMessage")
        XCTAssertEqual(vm.lastUsedProvider, .onDevice)
        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.first?.content, "端侧回复")
    }

    /// switchTo 加载目标会话的多条历史消息（替代 loadHistory 概念）
    func testSwitchToLoadsMultipleHistoricalMessages() throws {
        let vm = ChatViewModel()
        let conv = Conversation(title: "历史", systemPrompt: "你是助手")
        context.insert(conv)
        for content in ["历史消息1", "历史消息2", "历史消息3"] {
            let msg = ChatMessage(role: "user", content: content)
            msg.conversation = conv
            conv.messages.append(msg)
        }
        try context.save()

        vm.switchTo(conversation: conv)

        XCTAssertEqual(vm.messages.count, 3, "应加载全部 3 条历史消息")
        // SwiftData 返回顺序可能非插入顺序，用 Set 比较内容集合
        XCTAssertEqual(Set(vm.messages.map(\.content)), Set(["历史消息1", "历史消息2", "历史消息3"]))
    }

    /// switchTo 切换到空会话时清空 messages（替代 clearConversation 概念）
    func testSwitchToEmptyConversationClearsMessages() throws {
        let vm = ChatViewModel()
        vm.messages = [ChatMessage(role: "user", content: "旧消息")]
        let conv = Conversation(title: "空会话", systemPrompt: "")
        context.insert(conv)

        vm.switchTo(conversation: conv)

        XCTAssertTrue(vm.messages.isEmpty, "切换到空会话时 messages 应被清空")
    }

    /// resendMessage 设置 inputText 后触发发送流程（替代 regenerateLastMessage 概念）
    func testResendMessageSetsInputAndSends() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.resendMessage(content: "重发内容", in: conv, modelContext: context)

        XCTAssertEqual(vm.inputText, "", "resendMessage 后 inputText 应被清空（sendMessage 清空）")
        XCTAssertEqual(conv.messages.count, 1, "应追加 1 条用户消息")
        XCTAssertEqual(conv.messages.first?.role, "user")
        XCTAssertEqual(conv.messages.first?.content, "重发内容")
        XCTAssertTrue(vm.isLoading, "resendMessage 后 isLoading 应为 true")

        // 等待后台 processMessage 完成
        for _ in 0..<100 {
            if !vm.isLoading { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(vm.isLoading)
    }

    /// processMessage 将 conversation.systemPrompt 传入 ChatConfig（替代 updateSystemPrompt 概念）
    func testProcessMessagePassesSystemPromptToConfig() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是翻译官")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(mock.capturedConfig?.systemPrompt, "你是翻译官",
                       "ChatConfig.systemPrompt 应来自 conversation.systemPrompt")
    }

    /// sendMessage 无 pendingImage 时用户消息不应附带图片
    func testSendMessageWithoutPendingImageKeepsAttachedImageNil() throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        vm.pendingImage = nil
        vm.inputText = "纯文本"

        vm.sendMessage(in: conv, modelContext: context)

        XCTAssertNil(conv.messages.first?.attachedImage, "无 pendingImage 时 attachedImage 应为 nil")
        XCTAssertNil(vm.pendingImage, "pendingImage 应保持 nil")
    }

    /// sendMessage 空输入守卫提前返回时不清空 pendingImage（多模态图片守卫）
    func testSendMessageEmptyInputDoesNotClearPendingImage() throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let imageData = Data([0xFF])
        vm.pendingImage = imageData
        vm.inputText = "   "  // 空白输入

        vm.sendMessage(in: conv, modelContext: context)

        XCTAssertEqual(vm.pendingImage, imageData, "空输入守卫提前返回时 pendingImage 不应被清空")
        XCTAssertEqual(conv.messages.count, 0, "不应创建任何消息")
    }

    /// isRecording 默认值为 false
    func testIsRecordingDefaultsFalse() {
        let vm = ChatViewModel()
        XCTAssertFalse(vm.isRecording, "isRecording 默认应为 false")
    }

    /// speakingMessageId 默认值为 nil
    func testSpeakingMessageIdDefaultsNil() {
        let vm = ChatViewModel()
        XCTAssertNil(vm.speakingMessageId, "speakingMessageId 默认应为 nil")
    }

    /// toggleSpeak 连续切换多个消息 id，speakingMessageId 应跟随最后一条；再次点击同一条停止
    func testToggleSpeakAcrossMultipleMessages() {
        let vm = ChatViewModel()
        let id1 = UUID(), id2 = UUID(), id3 = UUID()

        vm.toggleSpeak(messageId: id1, content: "a")
        XCTAssertEqual(vm.speakingMessageId, id1)
        vm.toggleSpeak(messageId: id2, content: "b")
        XCTAssertEqual(vm.speakingMessageId, id2)
        vm.toggleSpeak(messageId: id3, content: "c")
        XCTAssertEqual(vm.speakingMessageId, id3, "连续切换后应跟随最后一条 id")
        // 再次点击同一条应停止
        vm.toggleSpeak(messageId: id3, content: "c")
        XCTAssertNil(vm.speakingMessageId, "同 id 再次点击应停止朗读")
    }

    /// sendMessage 清空预置的 currentToolSteps（状态清理）
    func testSendMessageClearsCurrentToolSteps() throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.currentToolSteps = [ChatViewModel.ToolStep(
            toolName: "calculate", status: .running, result: nil,
            thought: nil, arguments: "{}", loopIndex: 1
        )]
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        vm.inputText = "你好"

        vm.sendMessage(in: conv, modelContext: context)

        XCTAssertTrue(vm.currentToolSteps.isEmpty, "sendMessage 应清空 currentToolSteps")
    }

    /// errorMessage 被新错误覆盖（apiKey 缺失覆盖旧错误信息）
    func testErrorMessageOverwrittenByAPIKeyMissingError() async throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .deepseek
        vm.errorMessage = "旧错误信息"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.errorMessage, LLMError.apiKeyMissing.userMessage,
                       "apiKey 缺失错误应覆盖旧 errorMessage")
    }

    /// Qwen provider apiKey 缺失时设置 errorMessage（错误分支覆盖不同 provider）
    func testQwenProviderAPIKeyMissingSetsError() async throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .qwen
        // 不保存 apiKey

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.errorMessage, LLMError.apiKeyMissing.userMessage,
                       "Qwen 无 apiKey 时应设置 apiKeyMissing 错误")
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.streamingText, "")
    }

    /// 语义缓存写入后命中：首次请求写入缓存，第二次同 query 同 embedding 命中缓存（即使 mock chunks 已变）
    func testCacheWriteThenHitReturnsCachedResponse() async throws {
        let embedding: [Float] = [0.9, 0.1, 0.0]
        let mock = MockLLMProvider()
        mock.embedResult = [embedding]
        mock.chatChunks = ["原始回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        // 首次调用：走 LLM，写入缓存
        await vm.processMessage("你好", conversation: conv, modelContext: context)
        let firstAssistant = conv.messages.filter { $0.role == "assistant" }.last
        XCTAssertEqual(firstAssistant?.content, "原始回复", "首次应返回 LLM 响应")

        // 修改 mock chunks，验证第二次命中缓存而非新 chunks
        mock.chatChunks = ["新回复"]
        await vm.processMessage("你好", conversation: conv, modelContext: context)
        let secondAssistant = conv.messages.filter { $0.role == "assistant" }.last
        XCTAssertEqual(secondAssistant?.content, "原始回复",
                       "第二次应命中缓存返回原始回复，而非新的 mock chunks")
    }

    /// processMessage 完成后填充 lastDebugInfo（provider / fallbackUsed / apiResponse）
    func testLastDebugInfoPopulatedAfterProcessMessage() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["调试回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertNotNil(vm.lastDebugInfo, "processMessage 后应填充 lastDebugInfo")
        XCTAssertEqual(vm.lastDebugInfo?.apiResponse, "调试回复")
        XCTAssertEqual(vm.lastDebugInfo?.provider, vm.lastUsedProvider?.displayName)
        XCTAssertFalse(vm.lastDebugInfo?.fallbackUsed ?? true, "非降级时 fallbackUsed 应为 false")
    }

    /// streamingText 在 sendMessage 时被重置为空字符串（即便预置了残留值）
    func testSendMessageResetsStreamingText() throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.streamingText = "残留流式文本"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        vm.inputText = "你好"

        vm.sendMessage(in: conv, modelContext: context)

        XCTAssertEqual(vm.streamingText, "", "sendMessage 应重置 streamingText 为空字符串")
    }

    // MARK: - 深度补充测试 Phase 3：默认值 / 反馈闭环 / ReAct 边界 / 通知 / 缓存守卫

    /// 验证 ChatViewModel 初始状态默认值
    func testDefaultsInitialState() {
        let vm = ChatViewModel()
        XCTAssertTrue(vm.messages.isEmpty, "messages 默认应为空数组")
        XCTAssertEqual(vm.inputText, "", "inputText 默认应为空")
        XCTAssertFalse(vm.isLoading, "isLoading 默认应为 false")
        XCTAssertEqual(vm.streamingText, "", "streamingText 默认应为空")
        XCTAssertNil(vm.errorMessage, "errorMessage 默认应为 nil")
        XCTAssertTrue(vm.currentToolSteps.isEmpty, "currentToolSteps 默认应为空")
        XCTAssertFalse(vm.ragEnabled, "ragEnabled 默认应为 false")
        XCTAssertFalse(vm.toolsEnabled, "toolsEnabled 默认应为 false")
        XCTAssertEqual(vm.tokenLimit, 4000, "tokenLimit 默认应为 4000")
        XCTAssertEqual(vm.modelSelectionMode, "auto", "modelSelectionMode 默认应为 auto")
        XCTAssertEqual(vm.selectedProvider, .deepseek, "selectedProvider 默认应为 .deepseek")
        XCTAssertNil(vm.fallbackProvider, "fallbackProvider 默认应为 nil")
        XCTAssertFalse(vm.bffConfig.enabled, "bffConfig.enabled 默认应为 false")
        XCTAssertEqual(vm.currentNetworkStatus, .online, "currentNetworkStatus 默认应为 .online")
        XCTAssertTrue(vm.currentCitations.isEmpty, "currentCitations 默认应为空")
        XCTAssertNil(vm.pendingImage, "pendingImage 默认应为 nil")
        XCTAssertNil(vm.lastDebugInfo, "lastDebugInfo 默认应为 nil")
        XCTAssertTrue(vm.feedbackStates.isEmpty, "feedbackStates 默认应为空")
        XCTAssertNil(vm.feedbackToast, "feedbackToast 默认应为 nil")
        XCTAssertNil(vm.lastUsedProvider, "lastUsedProvider 默认应为 nil")
        XCTAssertFalse(vm.didFallbackLastRequest, "didFallbackLastRequest 默认应为 false")
    }

    // MARK: - 反馈闭环（handleFeedback / submitFeedback）

    /// handleFeedback 点赞：设置 feedbackStates[true] 和 feedbackToast
    func testHandleFeedbackPositiveSetsState() {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)

        XCTAssertEqual(vm.feedbackStates[msgId], true, "点赞后 feedbackStates 应为 true")
        XCTAssertNotNil(vm.feedbackToast, "点赞后应设置 feedbackToast")
    }

    /// handleFeedback 踩：设置 feedbackStates[false] 和 feedbackToast
    func testHandleFeedbackNegativeSetsState() {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)

        XCTAssertEqual(vm.feedbackStates[msgId], false, "踩后 feedbackStates 应为 false")
        XCTAssertNotNil(vm.feedbackToast, "踩后应设置 feedbackToast")
    }

    /// handleFeedback 相同状态再次点击取消反馈（toggle 行为）
    func testHandleFeedbackToggleCancelsFeedback() {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        // 首次点赞
        vm.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        XCTAssertEqual(vm.feedbackStates[msgId], true)

        // 再次点击相同状态 → 取消
        vm.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        XCTAssertNil(vm.feedbackStates[msgId], "相同状态再次点击应取消反馈")
        XCTAssertNil(vm.feedbackToast, "取消后 feedbackToast 应为 nil")
    }

    /// handleFeedback 从赞切换到踩
    func testHandleFeedbackSwitchFromPositiveToNegative() {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        XCTAssertEqual(vm.feedbackStates[msgId], true)

        vm.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)
        XCTAssertEqual(vm.feedbackStates[msgId], false, "切换到踩后应为 false")
        XCTAssertNotNil(vm.feedbackToast, "切换后应设置 feedbackToast")
    }

    /// handleFeedback 持久化反馈到 SwiftData（通过 ChatStorage 读取验证）
    func testHandleFeedbackPersistsToStorage() {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)

        let storage = ChatStorage(modelContext: context)
        let feedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertNotNil(feedback, "handleFeedback 应持久化反馈记录")
        XCTAssertEqual(feedback?.isPositive, true)
    }

    /// handleFeedback 切换反馈状态时更新已有记录（而非创建新记录）
    func testHandleFeedbackUpdatesExistingFeedback() {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        // 首次点赞
        vm.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        // 切换为踩
        vm.handleFeedback(messageId: msgId, isPositive: false, modelContext: context)

        let storage = ChatStorage(modelContext: context)
        let feedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertEqual(feedback?.isPositive, false, "切换后反馈记录应为 false（踩）")
    }

    // MARK: - buildEffectiveSystemPrompt 边界覆盖

    /// buildEffectiveSystemPrompt 注入 preferredTools
    func testBuildEffectiveSystemPromptPreferredTools() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.preferredTools = ["calculate", "weather"]
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"))
        XCTAssertTrue(result.contains("calculate"))
        XCTAssertTrue(result.contains("weather"))
        XCTAssertTrue(result.contains("、"), "偏好工具应以「、」分隔")
    }

    /// buildEffectiveSystemPrompt 注入 customFact
    func testBuildEffectiveSystemPromptCustomFact() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.customFact = "我是素食者"
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"))
        XCTAssertTrue(result.contains("我是素食者"))
    }

    /// buildEffectiveSystemPrompt 三个偏好同时注入
    func testBuildEffectiveSystemPromptAllCombined() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.preferredTone = "正式"
        pref.preferredTools = ["calculate"]
        pref.customFact = "我是素食者"
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertTrue(result.contains("【用户偏好】"))
        XCTAssertTrue(result.contains("语气：正式"))
        XCTAssertTrue(result.contains("calculate"))
        XCTAssertTrue(result.contains("我是素食者"))
        XCTAssertTrue(result.contains("；"), "多个偏好应以「；」分隔")
    }

    // MARK: - 模型名映射（Qwen provider）

    /// auto 模式 + Qwen provider：短文本映射到 qwen-plus，长文本映射到 qwq-32b
    func testModelSelectionAutoQwenRoutesToQwenModels() async throws {
        try KeychainManager.shared.saveAPIKey("test-key", for: .qwen)
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .qwen
        vm.modelSelectionMode = "auto"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        // 短文本 → qwen-plus
        await vm.processMessage("你好", conversation: conv, modelContext: context)
        XCTAssertEqual(mock.capturedConfig?.model, "qwen-plus",
                       "auto 模式 + Qwen 短文本应映射到 qwen-plus")

        // 长文本(>=50字) → qwq-32b
        let longText = String(repeating: "这是一段需要深度推理的长文本。", count: 5)
        await vm.processMessage(longText, conversation: conv, modelContext: context)
        XCTAssertEqual(mock.capturedConfig?.model, "qwq-32b",
                       "auto 模式 + Qwen 长文本应映射到 qwq-32b")
    }

    // MARK: - ReAct 循环边界

    /// ReAct 循环达到最大轮次（5轮）且无文本产出时设置超限 errorMessage
    func testReActLoopMaxIterationsSetsError() async throws {
        let mock = MockLLMProvider()
        mock.repeatToolCalls = true  // 每轮都 yield toolCalls，使循环达到上限
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"1 + 1\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "循环测试")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("循环测试", conversation: conv, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "超过最大轮次应设置 errorMessage")
        XCTAssertTrue(vm.errorMessage?.contains("5") == true,
                       "错误消息应包含最大轮次数 5")
        XCTAssertFalse(vm.isLoading, "超限后 isLoading 应为 false")
    }

    /// 一次响应包含多个工具调用：均执行成功并追加对应 tool 消息
    func testMultipleToolCallsInOneResponse() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"1 + 1\"}"),
            AccumulatedToolCall(id: "call-2", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"2 + 2\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算 1+1 和 2+2")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算 1+1 和 2+2", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 2, "应创建 2 个 ToolStep")
        XCTAssertEqual(vm.currentToolSteps[0].toolName, "calculate")
        XCTAssertEqual(vm.currentToolSteps[0].status, .completed)
        XCTAssertEqual(vm.currentToolSteps[0].result, "2")
        XCTAssertEqual(vm.currentToolSteps[1].toolName, "calculate")
        XCTAssertEqual(vm.currentToolSteps[1].status, .completed)
        XCTAssertEqual(vm.currentToolSteps[1].result, "4")
        let toolMsgs = conv.messages.filter { $0.role == "tool" }
        XCTAssertEqual(toolMsgs.count, 2, "应追加 2 条 tool 消息")
    }

    /// 工具调用带 thought 文本：chunkContent 非空时 ToolStep.thought 应记录决策文本
    func testToolCallWithThoughtText() async throws {
        let mock = MockLLMProvider()
        mock.toolChatResponse = "我需要计算一下"
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"1 + 1\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算 1+1")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算 1+1", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1)
        XCTAssertEqual(vm.currentToolSteps[0].thought, "我需要计算一下",
                       "chunkContent 非空时 thought 应记录决策文本")
    }

    // MARK: - UITEST 错误模式

    /// UITEST_FORCE_LLM_ERROR 模式：processMessage 短路设置固定错误消息
    func testProcessMessageForceLLMErrorUITESTMode() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.arguments.contains("UITEST_FORCE_LLM_ERROR"),
            "需以 -UITEST_FORCE_LLM_ERROR 启动参数运行"
        )
        let vm = ChatViewModel()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.errorMessage, "请先在设置中配置 API Key",
                       "UITEST_FORCE_LLM_ERROR 模式应设置固定错误消息")
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.streamingText, "")
    }

    // MARK: - 错误通知处理（.llmErrorOccurred）

    /// .llmErrorOccurred 通知（LLMError 类型）设置 errorMessage 并复位 isLoading/streamingText
    func testErrorNotificationSetsErrorMessage() async throws {
        let vm = ChatViewModel()
        vm.isLoading = true
        vm.streamingText = "残留流式文本"
        vm.errorMessage = nil

        let error = LLMError.apiKeyInvalid
        NotificationCenter.default.post(
            name: .llmErrorOccurred,
            object: nil,
            userInfo: ["error": error]
        )

        // 通知在后台 OperationQueue 异步处理，轮询等待主线程更新
        for _ in 0..<50 {
            if vm.errorMessage != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(vm.errorMessage, error.userMessage,
                       "LLMError 通知应设置 errorMessage 为 userMessage")
        XCTAssertFalse(vm.isLoading, "通知后 isLoading 应为 false")
        XCTAssertEqual(vm.streamingText, "", "通知后 streamingText 应被清空")
    }

    /// .llmErrorOccurred 通知（String message 类型）设置 errorMessage
    func testErrorNotificationWithStringMessage() async throws {
        let vm = ChatViewModel()
        vm.errorMessage = nil

        NotificationCenter.default.post(
            name: .llmErrorOccurred,
            object: nil,
            userInfo: ["message": "自定义错误消息"]
        )

        for _ in 0..<50 {
            if vm.errorMessage != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(vm.errorMessage, "自定义错误消息",
                       "String message 通知应设置 errorMessage")
        XCTAssertFalse(vm.isLoading)
    }

    /// .llmErrorOccurred 通知：相同 errorMessage 不重复设置（去重逻辑）
    /// 去重只影响 errorMessage，isLoading 仍应被复位
    func testErrorNotificationDoesNotOverwriteSameMessage() async throws {
        let vm = ChatViewModel()
        let sameMessage = LLMError.apiKeyMissing.userMessage
        vm.errorMessage = sameMessage
        vm.isLoading = true  // 去重不影响 isLoading 复位

        NotificationCenter.default.post(
            name: .llmErrorOccurred,
            object: nil,
            userInfo: ["message": sameMessage]
        )

        // 等待通知处理完成（isLoading 被复位）
        for _ in 0..<50 {
            if !vm.isLoading { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(vm.errorMessage, sameMessage, "errorMessage 应保持不变（去重）")
        XCTAssertFalse(vm.isLoading, "isLoading 仍应被复位（去重不影响 isLoading）")
    }

    // MARK: - 缓存写入守卫

    /// 工具模式启用时不写入缓存（避免工具调用中间结果污染缓存）
    func testCacheNotWrittenWhenToolsEnabled() async throws {
        let embedding: [Float] = [0.5, 0.5, 0.0]
        let mock = MockLLMProvider()
        mock.toolChatResponse = "工具模式回复"
        mock.embedResult = [embedding]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        // 首次：工具模式，不应写缓存
        await vm.processMessage("缓存守卫测试", conversation: conv, modelContext: context)

        // 第二次：关闭工具模式，应走 LLM 而非缓存
        vm.toolsEnabled = false
        mock.toolChatResponse = nil
        mock.chatChunks = ["非缓存回复"]
        await vm.processMessage("缓存守卫测试", conversation: conv, modelContext: context)

        // 用 vm.messages（普通数组）而非 conv.messages（SwiftData 关系，顺序不确定）
        let lastAssistant = vm.messages.filter { $0.role == "assistant" }.last
        XCTAssertEqual(lastAssistant?.content, "非缓存回复",
                       "工具模式不应写缓存，关闭工具后应返回新 LLM 响应而非缓存")
    }

    /// 空响应不写入缓存（fullResponse 为空时跳过 cache.set）
    func testCacheNotWrittenWhenResponseEmpty() async throws {
        let embedding: [Float] = [1.0, 0.0, 0.0]
        let mock = MockLLMProvider()
        mock.embedResult = [embedding]
        mock.chatChunks = []  // 空 chunks → fullResponse 为空
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = false
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("空响应测试", conversation: conv, modelContext: context)

        // 直接查询缓存，验证未被写入
        let cached = vm.cache.get(query: "空响应测试", embedding: embedding)
        XCTAssertNil(cached, "空响应不应写入缓存")
    }

    // MARK: - 调试信息（lastDebugInfo）字段填充

    /// lastDebugInfo 在工具调用模式下填充 toolCalls 字段
    func testLastDebugInfoToolCallsPopulated() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"1 + 2\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        XCTAssertNotNil(vm.lastDebugInfo)
        XCTAssertEqual(vm.lastDebugInfo?.toolCalls.count, 1, "应填充 1 个 toolCall 调试信息")
        XCTAssertEqual(vm.lastDebugInfo?.toolCalls.first?.toolName, "calculate")
        XCTAssertEqual(vm.lastDebugInfo?.toolCalls.first?.result, "3")
    }

    /// lastDebugInfo 的 embeddingDimension 反映 queryEmbedding 维度
    func testLastDebugInfoEmbeddingDimension() async throws {
        let embedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let mock = MockLLMProvider()
        mock.embedResult = [embedding]
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = false
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.lastDebugInfo?.embeddingDimension, 5,
                       "embeddingDimension 应为 embedding 向量维度 5")
    }

    // MARK: - 流式中切换会话（switchTo 取消）

    /// switchTo 在流式输出进行中取消任务并立即清理状态
    func testSwitchToCancelsStreamingAndClearsState() throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["chunk1", "chunk2", "chunk3"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv1 = Conversation(title: "会话1", systemPrompt: "你是助手")
        context.insert(conv1)
        vm.inputText = "你好"
        vm.sendMessage(in: conv1, modelContext: context)
        XCTAssertTrue(vm.isLoading, "sendMessage 后应处于 loading 状态")

        // 切换到新会话（streamingTask 应被取消）
        let conv2 = Conversation(title: "会话2", systemPrompt: "你是助手")
        context.insert(conv2)
        let msg = ChatMessage(role: "user", content: "历史消息")
        msg.conversation = conv2
        conv2.messages.append(msg)
        try context.save()

        vm.switchTo(conversation: conv2)

        XCTAssertFalse(vm.isLoading, "switchTo 应取消流式并复位 isLoading")
        XCTAssertEqual(vm.streamingText, "", "switchTo 应清空 streamingText")
        XCTAssertEqual(vm.messages.count, 1, "应加载目标会话消息")
        XCTAssertEqual(vm.messages.first?.content, "历史消息")
    }

    /// limitTokens 保留最近消息（尾部累加截断策略验证）
    func testLimitTokensKeepsMostRecentMessages() {
        let vm = ChatViewModel()
        vm.tokenLimit = 6
        // 每条 2 tokens（"a b" → 2 词 → 2 tokens），limit=6 应保留最近 3 条
        let messages = ["a b", "c d", "e f", "g h", "i j"].map {
            APIMessage(role: "user", content: $0, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        }
        let limited = vm.limitTokens(messages, max: 6)
        XCTAssertEqual(limited.count, 3, "limit=6 时应保留最近 3 条（每条 2 tokens）")
        XCTAssertEqual(limited.last?.content, "i j", "应保留最后一条")
        XCTAssertEqual(limited.first?.content, "e f", "应从 e f 开始保留")
    }

    // MARK: - 深度补充测试 Phase 4：工具调用边界 / 反馈边界 / 通知边界 / 会话切换

    /// 工具调用带无效 JSON 参数：args 解析为空字典 {}，工具仍应执行
    func testToolCallWithInvalidJSONArguments() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "{invalid json}")  // 无效 JSON
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        // 无效 JSON → args 为空字典 → calculate 工具因缺少 expression 应失败
        XCTAssertEqual(vm.currentToolSteps.count, 1)
        XCTAssertEqual(vm.currentToolSteps[0].status, .failed,
                       "无效 JSON 参数导致 calculate 缺少 expression，应为 .failed")
    }

    /// 工具调用带空字符串参数：args 解析为空字典
    func testToolCallWithEmptyStringArguments() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1)
        // 空字符串 → JSONSerialization 失败 → args 为 [:] → calculate 缺少 expression → .failed
        XCTAssertEqual(vm.currentToolSteps[0].status, .failed)
    }

    /// handleFeedback 的 feedbackToast 在 2 秒后应自动清除
    func testHandleFeedbackToastAutoClears() async throws {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.handleFeedback(messageId: msgId, isPositive: true, modelContext: context)
        XCTAssertNotNil(vm.feedbackToast, "点赞后应设置 feedbackToast")

        // 等待 2.5 秒让自动清除 Task 执行
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertNil(vm.feedbackToast, "2 秒后 feedbackToast 应被自动清除")
    }

    /// submitFeedback 对已存在的反馈记录应调用 updateFeedback 而非 saveFeedback
    func testSubmitFeedbackUpdatesExistingFeedback() {
        let vm = ChatViewModel()
        let msgId = UUID()
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        // 首次点赞
        vm.submitFeedback(messageId: msgId, isPositive: true, citations: [], modelContext: context)
        let storage = ChatStorage(modelContext: context)
        let firstFeedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertNotNil(firstFeedback)
        XCTAssertEqual(firstFeedback?.isPositive, true)

        // 切换为踩（update 路径）
        vm.submitFeedback(messageId: msgId, isPositive: false, citations: [], modelContext: context)
        let updatedFeedback = storage.fetchFeedback(messageId: msgId)
        XCTAssertNotNil(updatedFeedback)
        XCTAssertEqual(updatedFeedback?.isPositive, false, "切换后应为 false（踩）")
    }

    /// switchTo 连续调用多次应正确切换 messages
    func testSwitchToMultipleTimes() throws {
        let vm = ChatViewModel()
        let conv1 = Conversation(title: "会话1", systemPrompt: "你是助手1")
        let conv2 = Conversation(title: "会话2", systemPrompt: "你是助手2")
        let conv3 = Conversation(title: "会话3", systemPrompt: "你是助手3")
        context.insert(conv1)
        context.insert(conv2)
        context.insert(conv3)

        let msg1 = ChatMessage(role: "user", content: "消息1")
        msg1.conversation = conv1
        conv1.messages.append(msg1)
        let msg2 = ChatMessage(role: "user", content: "消息2")
        msg2.conversation = conv2
        conv2.messages.append(msg2)
        let msg3 = ChatMessage(role: "user", content: "消息3")
        msg3.conversation = conv3
        conv3.messages.append(msg3)
        try context.save()

        vm.switchTo(conversation: conv1)
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.content, "消息1")

        vm.switchTo(conversation: conv2)
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.content, "消息2")

        vm.switchTo(conversation: conv3)
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.content, "消息3")
    }

    /// .llmErrorOccurred 通知无 userInfo 时不应设置 errorMessage
    func testErrorNotificationWithNoUserInfoDoesNotSetError() async throws {
        let vm = ChatViewModel()
        vm.errorMessage = nil

        NotificationCenter.default.post(name: .llmErrorOccurred, object: nil, userInfo: nil)

        // 等待潜在的通知处理
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(vm.errorMessage, "无 userInfo 的通知不应设置 errorMessage")
    }

    /// .llmErrorOccurred 通知 userInfo 缺少 error 和 message 键时不应设置 errorMessage
    func testErrorNotificationWithEmptyUserInfoDoesNotSetError() async throws {
        let vm = ChatViewModel()
        vm.errorMessage = nil

        NotificationCenter.default.post(name: .llmErrorOccurred, object: nil, userInfo: [:])

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(vm.errorMessage, "空 userInfo 的通知不应设置 errorMessage")
    }

    /// limitTokens 单条消息超过 limit 时应返回空数组
    func testLimitTokensSingleMessageExceedsLimit() {
        let vm = ChatViewModel()
        vm.tokenLimit = 1
        // "a b c d e" → 5 词 → Int(6.5) = 6 tokens > 1
        let messages = [APIMessage(role: "user", content: "a b c d e",
                                   images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
        let limited = vm.limitTokens(messages, max: 1)
        XCTAssertTrue(limited.isEmpty, "单条消息超过 limit 时应返回空数组")
    }

    /// buildEffectiveSystemPrompt 所有偏好默认（tone="默认"）时应返回原 base
    func testBuildEffectiveSystemPromptDefaultToneReturnsBase() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        pref.preferredTone = "默认"  // 默认值
        let result = vm.buildEffectiveSystemPrompt(base: "你是助手", preference: pref)
        XCTAssertEqual(result, "你是助手", "tone 为默认值时不应注入偏好")
    }

    /// buildEffectiveSystemPrompt 空 base + 空 preference 应返回空字符串
    func testBuildEffectiveSystemPromptEmptyBaseEmptyPreference() {
        let vm = ChatViewModel()
        let pref = UserPreference()
        let result = vm.buildEffectiveSystemPrompt(base: "", preference: pref)
        XCTAssertEqual(result, "", "空 base + 空 preference 应返回空字符串")
    }

    /// resendMessage 空内容应走 sendMessage 守卫，不创建消息
    func testResendMessageWithEmptyContent() async throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.resendMessage(content: "   ", in: conv, modelContext: context)

        XCTAssertEqual(conv.messages.count, 0, "空白内容 resendMessage 不应创建消息")
        XCTAssertFalse(vm.isLoading, "空白内容不应触发 isLoading")
    }

    /// onDevice + toolsEnabled + 在线（默认状态）→ effectiveProviderForRequest 降级到 fallback provider。
    /// currentNetworkStatus 默认为 .online（init 中设置），无需额外修改。
    func testOnDeviceWithToolsEnabledOnlineDegradesToFallback() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["降级回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        // currentNetworkStatus 默认为 .online（private(set)，无法从外部修改）
        XCTAssertEqual(vm.currentNetworkStatus, .online, "默认网络状态应为 online")
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        // onDevice + toolsEnabled + online → effectiveProvider = .onDevice.fallback = .deepseek
        XCTAssertNotEqual(vm.lastUsedProvider, .onDevice,
                          "在线 + 工具开启时应降级到 fallback provider")
        XCTAssertFalse(vm.didFallbackLastRequest, "未触发 FallbackLLMProvider 降级（使用 effectiveProvider）")
        XCTAssertNil(vm.errorMessage, "降级到云端 provider 不应设置错误")
    }

    /// toggleSpeak 后切换会话：speakingMessageId 应被 switchTo 清空
    func testSwitchToClearsSpeakingMessageId() throws {
        let vm = ChatViewModel()
        let id = UUID()
        vm.speakingMessageId = id  // 模拟正在朗读

        let conv = Conversation(title: "新会话", systemPrompt: "")
        context.insert(conv)

        vm.switchTo(conversation: conv)

        // switchTo 清理 streamingText 和 isLoading，但 speakingMessageId 由 voiceService delegate 管理
        // 此处验证 switchTo 不直接影响 speakingMessageId（它由 toggleSpeak / onSpeakFinished 管理）
        // 但 streamingText 和 isLoading 应被清空
        XCTAssertEqual(vm.streamingText, "")
        XCTAssertFalse(vm.isLoading)
    }

    /// sendMessage 后 selectedModel 应保持不变
    func testSendMessagePreservesSelectedModel() throws {
        let mock = MockLLMProvider()
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.selectedModel = "custom-model"
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)

        vm.inputText = "你好"
        vm.sendMessage(in: conv, modelContext: context)

        XCTAssertEqual(vm.selectedModel, "custom-model",
                       "sendMessage 不应修改 selectedModel")
    }

    /// lastDebugInfo 的 promptJSON 应为有效 JSON
    func testLastDebugInfoPromptJSONIsValidJSON() async throws {
        let mock = MockLLMProvider()
        mock.chatChunks = ["回复"]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "你好")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("你好", conversation: conv, modelContext: context)

        XCTAssertNotNil(vm.lastDebugInfo)
        let promptJSON = vm.lastDebugInfo?.promptJSON ?? ""
        XCTAssertFalse(promptJSON.isEmpty, "promptJSON 不应为空")
        // 验证是有效 JSON
        let jsonData = promptJSON.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        XCTAssertNotNil(parsed, "promptJSON 应为有效 JSON 数组")
        XCTAssertGreaterThan(parsed?.count ?? 0, 0, "promptJSON 应包含至少 1 条消息")
    }

    /// multiple tool calls 混合成功与失败：成功标记 completed，失败标记 failed
    func testMultipleToolCallsMixedSuccessAndFailure() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"1 + 1\"}"),  // 成功
            AccumulatedToolCall(id: "call-2", type: "function", name: "nonexistent_tool",
                                arguments: "{}")  // 失败
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "混合测试")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("混合测试", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 2, "应创建 2 个 ToolStep")
        XCTAssertEqual(vm.currentToolSteps[0].status, .completed, "calculate 应成功")
        XCTAssertEqual(vm.currentToolSteps[1].status, .failed, "nonexistent_tool 应失败")
    }

    /// processMessage 完成后 streamingText 最终值为空
    func testProcessMessageCleansStreamingTextAfterToolCall() async throws {
        let mock = MockLLMProvider()
        mock.toolChatResponse = "思考中"
        mock.toolCalls = [
            AccumulatedToolCall(id: "call-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"1 + 1\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算 1+1")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算 1+1", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.streamingText, "", "工具调用完成后 streamingText 应被清空")
        XCTAssertFalse(vm.isLoading, "完成后 isLoading 应为 false")
    }
}

/// 用于单元测试的 LLMProvider 桩实现：chat 返回可配置的流式 chunk，embed 返回预设结果。
/// 避免在测试中发起真实网络请求。默认 chatChunks 为空时流立即 finish（保持向后兼容）。
final class MockLLMProvider: LLMProvider {
    /// embed 返回的预设 embedding 二维数组（默认空）
    var embedResult: [[Float]] = []
    /// 纯文本 chat 流式返回的 chunk 序列（默认空 → 流立即 finish）
    var chatChunks: [String] = []
    /// 工具 chat 流式返回的文本内容（nil → 不 yield content）
    var toolChatResponse: String?
    /// 工具调用列表（仅在 tools-chat 首次调用时 yield 一次，避免 ReAct 循环无限触发）
    var toolCalls: [AccumulatedToolCall]?
    /// 捕获最近一次 chat 调用的 config（用于验证模型选择）
    private(set) var capturedConfig: ChatConfig?
    /// 捕获最近一次 chat 调用的 apiKey
    private(set) var capturedApiKey: String?
    /// 标记 toolCalls 是否已 yield（避免 ReAct 循环重复触发）
    private var toolCallsYielded = false
    /// 是否每轮都 yield toolCalls（true 时不设置 toolCallsYielded，用于测试 ReAct 循环上限）
    var repeatToolCalls: Bool = false

    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        capturedConfig = config
        capturedApiKey = apiKey
        return AsyncStream { cont in
            for chunk in self.chatChunks {
                cont.yield(chunk)
            }
            cont.finish()
        }
    }

    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        capturedConfig = config
        capturedApiKey = apiKey
        return AsyncStream { cont in
            if let resp = self.toolChatResponse {
                cont.yield(ParsedChunk(content: resp, toolCalls: nil))
            }
            if let calls = self.toolCalls {
                // repeatToolCalls=true 时每轮都 yield（用于测试 ReAct 循环上限）
                if self.repeatToolCalls {
                    cont.yield(ParsedChunk(content: nil, toolCalls: calls))
                } else if !self.toolCallsYielded {
                    cont.yield(ParsedChunk(content: nil, toolCalls: calls))
                    self.toolCallsYielded = true
                }
            }
            cont.finish()
        }
    }

    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        embedResult
    }
}
