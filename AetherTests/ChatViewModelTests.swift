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
        XCTAssertEqual(conv.messages.last?.role, "assistant")
        XCTAssertEqual(conv.messages.last?.content, "这是回复")
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
            if let calls = self.toolCalls, !self.toolCallsYielded {
                cont.yield(ParsedChunk(content: nil, toolCalls: calls))
                self.toolCallsYielded = true
            }
            cont.finish()
        }
    }

    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        embedResult
    }
}
