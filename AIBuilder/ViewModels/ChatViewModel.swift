import Foundation
import SwiftData
#if os(iOS)
import ActivityKit
#endif

/// 核心 ViewModel，管理聊天消息、流式输出、工具调用、RAG 检索、语音输入输出、灵动岛 Live Activity。
/// 使用 @Observable + @MainActor 隔离。
@Observable
@MainActor
final class ChatViewModel {
    /// 当前会话消息列表
    var messages: [ChatMessage] = []
    /// 输入框文本
    var inputText = ""
    /// 是否正在等待/流式输出
    var isLoading = false
    /// 当前流式输出文本（实时更新）
    var streamingText = ""
    /// 错误消息（nil 表示无错误）
    var errorMessage: String?
    /// 当前 ReAct 循环的工具步骤列表
    var currentToolSteps: [ToolStep] = []
    /// 是否在发送消息前检索本地知识库
    var ragEnabled = false        // Day 3 启用
    /// 是否启用工具调用进入 ReAct 循环
    var toolsEnabled = false      // Day 4 启用
    /// 上下文 token 上限，超出时从尾部截断
    var tokenLimit = 4000
    /// 当前选中的 LLM 模型名
    var selectedModel: String = APIConfig.defaultModel
    /// Day 12: 模型选择模式（"auto"=智能路由 / "deepseek-chat" / "deepseek-reasoner"）
    /// "auto" 时由 SmartRouter 决定模型；其他值时用用户指定模型
    var modelSelectionMode: String = "auto"
    /// Day 13: 当前选中的 LLM 供应商（默认 .deepseek，向后兼容）
    var selectedProvider: ModelProvider = .deepseek
    /// Day 13: 备用供应商（nil=不降级；非 nil 时用 FallbackLLMProvider 装饰主 provider）
    var fallbackProvider: ModelProvider? = nil
    /// Day 15: BFF 代理配置（默认未启用；启用后请求经服务端中转，上游 API Key 不落设备）
    var bffConfig: BFFConfig = .default
    /// Day 16: 端侧推理配置（开关 / 模型路径 / 采样参数）
    var onDeviceConfig: OnDeviceConfig = .default
    /// Day 16: 断网自动切换前保存的原 provider，联网后切回
    private var originalSelectedProvider: ModelProvider?
    /// Day 16: 网络状态监听 Task（断网切端侧、联网切云端）
    private var networkStatusTask: Task<Void, Never>?
    /// Day 16: 当前网络状态（由 NetworkMonitor 更新，供 makeLLMProvider 同步判断是否降级）
    private(set) var currentNetworkStatus: NetworkStatus = .online
    /// Day 15: 客户端令牌桶限流器（BFF 模式下在调用 chat 前申请令牌，耗尽抛 rateLimited）
    private let rateLimiter = RateLimiter()
    /// Day 13: 最近一次请求实际命中的 provider（暴露给 DebugInfo，由 FallbackLLMProvider 写入）
    private(set) var lastUsedProvider: ModelProvider?
    /// Day 13: 最近一次请求是否触发了降级
    private(set) var didFallbackLastRequest: Bool = false
    /// Day 13: 标记 init 时是否注入了测试 client（注入则跳过工厂构造）
    private let injectedClientUsed: Bool
    /// 当前 RAG 检索的引用分块列表
    var currentCitations: [DocumentChunk] = []
    // Day 5 语音
    /// 是否正在录音
    var isRecording = false
    /// 正在朗读的消息 ID
    var speakingMessageId: UUID?
    // 补充 A：视觉多模态——待发送的图片
    /// 待发送的图片
    var pendingImage: Data?
    // 补充 C：调试面板——最近一次请求的调试信息
    /// 最近一次请求的调试信息
    var lastDebugInfo: DebugInfo?
    // Day 17: HealthKit 服务（默认 nil，由设置页注入）
    /// HealthKit 服务实例，nil 表示未启用健康上下文
    #if os(iOS)
    var healthKitService: HealthKitService?
    #endif
    /// Day 17: 是否在发送消息时注入健康上下文（最近 24h 睡眠/心率/步数）
    var injectHealthContext: Bool = false
    /// 每条助手消息的反馈状态（messageId -> true=赞 / false=踩），nil 表示未反馈
    var feedbackStates: [UUID: Bool] = [:]
    /// 反馈操作后的提示文本（如"感谢反馈"），nil 表示不显示
    var feedbackToast: String?
    /// TTS 朗读配置（音色/语速/音调/音量），由设置页同步更新，默认从 UserDefaults 加载
    var ttsConfig: TTSConfig = .load()

    // 测试性调整：把 client / cache 暴露为 internal 并支持注入，便于单元测试预置缓存命中或注入 Mock LLMProvider
    // 生产侧行为不变：默认参数 DeepSeekClient() / SemanticCache() 兜底
    /// LLMProvider，支持注入便于测试
    let client: LLMProvider
    /// RAG 服务（构建检索增强上下文）
    private let ragService = RAGService()
    /// 语义缓存（支持注入便于测试）
    let cache: SemanticCache
    /// 语音服务（录音识别 + 朗读）
    private let voiceService = VoiceService()
    /// 当前流式输出 Task（可取消）
    private var streamingTask: Task<Void, Never>?
    /// ReAct 循环最大轮次
    private let maxReActLoops = 5
    /// Day 8: 单工具执行超时（秒）。超时不中断 ReAct 循环，标记失败后继续下一轮。
    private let toolTimeout: TimeInterval = 15
    /// Day 10: 用 nonisolated(unsafe) 让 deinit 能访问
    nonisolated(unsafe) private var errorObserver: NSObjectProtocol?
    /// 补充 D：灵动岛 Live Activity 引用
    #if os(iOS)
    private var liveActivity: Activity<TimerActivityAttributes>?
    #endif

    /// 单个工具调用步骤的 UI 状态
    struct ToolStep: Identifiable {
        /// 唯一标识
        let id = UUID()
        /// 工具名
        let toolName: String
        /// 步骤状态
        var status: ToolStepStatus
        /// 工具执行结果
        var result: String?
        /// Day 8: assistant 此轮的决策文本（Thought 段）。可能为 nil（AI 仅返回 tool_calls 无文本）
        var thought: String?
        /// Day 8: 工具调用的参数 JSON 字符串（Action 段）
        var arguments: String
        /// Day 8: 当前 ReAct 轮次序号（从 1 开始）
        var loopIndex: Int
    }

    /// 工具步骤状态
    enum ToolStepStatus {
        case running, completed, failed
    }

    /// 初始化。client / cache 可注入为测试可替换，生产默认 DeepSeekClient() / SemanticCache() 兜底。
    /// 注册 errorObserver 监听 LLM 错误，设置 voiceService 朗读完成回调。
    init(client: LLMProvider? = nil, cache: SemanticCache? = nil) {
        self.client = client ?? DeepSeekClient()
        self.cache = cache ?? SemanticCache()
        self.injectedClientUsed = client != nil   // Day 13: 标记是否注入
        errorObserver = NotificationCenter.default.addObserver(
            forName: .llmErrorOccurred,
            object: nil,
            queue: OperationQueue()  // 改为后台 OperationQueue，避免主线程同步回调
        ) { [weak self] notification in
            guard let self = self else { return }
            // Day 10: 优先接收 LLMError，回退兼容旧的 String message
            var userMsg: String?
            if let err = notification.userInfo?["error"] as? LLMError {
                userMsg = err.userMessage
            } else if let msg = notification.userInfo?["message"] as? String {
                userMsg = msg
            }
            if let msg = userMsg {
                // Day 14: LLM 错误埋点 errorOccurred
                let errorType: String
                if let err = notification.userInfo?["error"] as? LLMError {
                    errorType = String(describing: err)
                    // Day 20: 上报异常到崩溃监控（Bugly 不可用时走占位分支）
                    CrashReportService.shared.reportException(err)
                } else {
                    errorType = "LLMError"
                    // Day 20: 非结构化错误也上报到崩溃监控
                    CrashReportService.shared.reportException(NSError(domain: "LLMError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
                }
                Task.detached { await TelemetryService.shared.track(.errorOccurred(errorType: errorType, userMessage: msg)) }
                // 切回主线程更新 UI
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // 去重：相同错误消息不重复设置
                    if self.errorMessage != msg {
                        self.errorMessage = msg
                    }
                    self.isLoading = false
                    self.streamingText = ""
                }
            }
        }
        // Day 5: 朗读完成时清空 speakingMessageId，避免按钮状态卡住
        voiceService.onSpeakFinished = { [weak self] in
            self?.speakingMessageId = nil
        }
        // Day 16: 若启用断网自动切换，启动网络状态监听
        if onDeviceConfig.autoSwitchOnNetworkLoss {
            startNetworkMonitoring()
        }
    }

    /// Day 10: 释放 errorObserver 避免泄漏
    deinit {
        // Day 10: 释放 errorObserver，避免泄漏
        // streamingTask 通过 .cancel() 在 switchTo / 新消息发送时已处理
        if let observer = errorObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Day 16: 端侧推理 / 网络监听

    /// 启动网络状态监听。断网时切到端侧推理，联网后切回原 provider。
    private func startNetworkMonitoring() {
        networkStatusTask?.cancel()
        networkStatusTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            // 启动全局 NetworkMonitor（内部幂等，多次调用安全）
            await NetworkMonitor.shared.start()
            // 订阅状态变化流，初始状态会立即 yield 一次
            let stream = await NetworkMonitor.shared.statusStream()
            for await status in stream {
                guard !Task.isCancelled else { return }
                self.currentNetworkStatus = status
                switch status {
                case .offline:
                    // 断网：切到端侧推理
                    self.switchToOnDevice()
                default:
                    // 联网（wifi/cellular/online）：切回原 provider
                    self.switchToOriginalProvider()
                }
            }
        }
    }

    /// 切换到端侧推理。保存当前 provider 供联网后恢复。
    func switchToOnDevice() {
        guard selectedProvider != .onDevice else { return }
        // 仅在未保存过原 provider 时保存，避免覆盖
        if originalSelectedProvider == nil {
            originalSelectedProvider = selectedProvider
        }
        selectedProvider = .onDevice
    }

    /// 切回原 provider（联网后恢复）。仅当当前处于端侧推理且有保存的原 provider 时生效。
    func switchToOriginalProvider() {
        guard selectedProvider == .onDevice, let original = originalSelectedProvider else { return }
        selectedProvider = original
        originalSelectedProvider = nil
    }

    /// Day 13: 按 selectedProvider / fallbackProvider 构造 LLMProvider。
    /// 生产侧：若 fallbackProvider != nil，返回 FallbackLLMProvider 装饰；否则返回单一 client。
    /// 测试侧：若 init 时注入了 client，则优先用注入的（绕过工厂）。
    /// Day 16: 端侧推理不支持工具调用，需工具且网络可用时通过 effectiveProviderForRequest 降级到云端。
    private func makeLLMProvider() -> LLMProvider {
        if injectedClientUsed {
            return self.client
        }
        let provider = effectiveProviderForRequest()
        // Day 15: BFF 模式启用时走 BFF 代理（服务端持有上游 key，设备只持 BFF Token）
        if bffConfig.enabled {
            return ModelProviderFactory.make(bffConfig: bffConfig, provider: provider)
        }
        let primary = ModelProviderFactory.make(provider)
        if let fb = fallbackProvider {
            let fallback = ModelProviderFactory.make(fb)
            return FallbackLLMProvider(primary: primary, fallback: fallback, primaryProvider: provider, fallbackProvider: fb)
        }
        return primary
    }

    /// Day 16: 计算本次请求实际使用的 provider。
    /// 端侧推理不支持工具调用，若需工具且网络可用则降级到云端 fallback provider。
    private func effectiveProviderForRequest() -> ModelProvider {
        if selectedProvider == .onDevice && toolsEnabled && currentNetworkStatus != .offline {
            return selectedProvider.fallback
        }
        return selectedProvider
    }

    /// Day 13: 把 SmartRouter 输出的模型名（"deepseek-chat" / "deepseek-reasoner"）映射到指定 provider 的对应模型名。
    /// - "deepseek-chat" → provider.defaultChatModel
    /// - "deepseek-reasoner" → provider.defaultReasonerModel
    /// - 其他 → 原值返回
    /// Day 16: 新增 provider 参数，使降级到云端时模型名映射到云端 provider 的模型。
    private func mapModelName(_ name: String, for provider: ModelProvider) -> String {
        switch name {
        case "deepseek-chat":
            return provider.defaultChatModel
        case "deepseek-reasoner":
            return provider.defaultReasonerModel
        default:
            return name
        }
    }

    // MARK: - Day 5 语音

    /// 切换语音输入。首次调用会请求权限，授权后开始/停止录音；识别结果实时写入 inputText。
    func toggleVoiceInput() {
        if isRecording {
            voiceService.stopRecording()
            isRecording = false
            voiceService.onRecognized = nil
            return
        }
        Task {
            let granted = await voiceService.requestPermission()
            guard granted else {
                errorMessage = "需要语音识别权限"
                return
            }
            // 开始录音前清空输入框与上一次识别结果
            inputText = ""
            voiceService.recognizedText = ""
            voiceService.onRecognized = { [weak self] text in
                self?.inputText = text
            }
            do {
                try voiceService.startRecording()
                isRecording = voiceService.isRecording
            } catch {
                // 录音启动失败（如音频会话激活失败 / 识别器不可用）：避免按钮卡住
                isRecording = false
                voiceService.onRecognized = nil
                errorMessage = "录音启动失败: \(error.localizedDescription)"
            }
        }
    }

    /// 切换语音朗读。点击同一条消息则停止；点击另一条则切换。
    func toggleSpeak(messageId: UUID, content: String) {
        if speakingMessageId == messageId {
            voiceService.stopSpeaking()
            speakingMessageId = nil
            return
        }
        // 切换到新消息朗读（stopSpeaking 会触发 didCancel → onSpeakFinished，但这里同步设置避免状态抖动）
        voiceService.stopSpeaking()
        speakingMessageId = messageId
        voiceService.speak(content, config: ttsConfig)
    }

    /// 切换到指定会话：清理流式状态、加载该会话消息
    func switchTo(conversation: Conversation) {
        streamingTask?.cancel()
        streamingTask = nil
        streamingText = ""
        isLoading = false
        currentToolSteps = []
        currentCitations = []
        errorMessage = nil
        inputText = ""
        messages = conversation.messages
    }

    /// 发送当前 inputText。空 input 守卫不触发；附加 pendingImage；立即持久化用户消息防丢失；
    /// 启动 streamingTask 调用 processMessage 处理后续流式输出。
    func sendMessage(in conversation: Conversation, modelContext: ModelContext) {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userMessage = ChatMessage(role: "user", content: inputText)
        // 补充 A：附加待发送图片
        if let imageData = pendingImage {
            userMessage.attachedImage = imageData
            pendingImage = nil
        }
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        messages.append(userMessage)
        let userInput = inputText
        inputText = ""
        isLoading = true
        streamingText = ""
        currentToolSteps = []
        // 补充 D：启动灵动岛
        startLiveActivity(query: userInput)
        // 立即持久化用户消息，防止流式中途崩溃丢失
        try? modelContext.save()
        streamingTask = Task {
            await processMessage(userInput, conversation: conversation, modelContext: modelContext)
        }
    }

    /// 重新提问：将旧问题内容填入输入框并触发发送
    func resendMessage(content: String, in conversation: Conversation, modelContext: ModelContext) {
        inputText = content
        sendMessage(in: conversation, modelContext: modelContext)
    }

    /// 消息处理主流程：UIT 测试短路 → 读 apiKey → 注入偏好 systemPrompt → 计算 embedding → 缓存命中则跳过 ReAct → ReAct 循环 → 缓存写入 → 调试信息 → 关灵动岛。
    func processMessage(_ text: String, conversation: Conversation, modelContext: ModelContext) async {
        // UIT 测试模式：短路真实 HTTP/RAG/Tool，注入固定桩回复
        // 说明：避免 UIT 触发真实 HTTP，复用缓存命中的假打字路径驱动 UI 状态机
        if ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_NETWORK") {
            let stubReply = "（UIT 测试模式）已收到：\(text)"
            // 保持流式打字效果以驱动 UI 状态机（复用缓存命中的 4 char/8ms 假打字模式）
            isLoading = true
            streamingText = ""
            let chars = Array(stubReply)
            for piece in chars.chunked(into: 4) {
                if Task.isCancelled { return }
                streamingText += String(piece)
                try? await Task.sleep(nanoseconds: 8_000_000) // 8ms / 4 chars
            }
            // 收尾：追加 assistant 消息、清理 streamingText，与正常路径一致
            let assistantMsg = ChatMessage(role: "assistant", content: stubReply)
            assistantMsg.conversation = conversation
            conversation.messages.append(assistantMsg)
            messages.append(assistantMsg)
            streamingText = ""
            isLoading = false
            try? modelContext.save()
            endLiveActivity()
            return
        }

        // Day 13: 用工厂构造 LLMProvider（生产侧 FallbackLLMProvider 装饰，测试侧注入优先）
        let llmClient = makeLLMProvider()
        // Day 13: 初值为主 provider（若未触发降级，最终值即此）。缓存命中路径不走 LLMProvider 也要保证已设置。
        // Day 16: 端侧降级到云端时记录实际使用的 provider
        self.lastUsedProvider = effectiveProviderForRequest()
        self.didFallbackLastRequest = false

        // 后台线程读取 apiKey，避免主线程阻塞
        let apiKey = await Task.detached(priority: .userInitiated) {
            KeychainManager.shared.getAPIKey() ?? ""
        }.value

        // 补充 C：注入用户偏见到 systemPrompt 末尾（提取为 buildEffectiveSystemPrompt 便于单测）
        let preference = ChatStorage(modelContext: modelContext).fetchPreference()
        var effectiveSystemPrompt = buildEffectiveSystemPrompt(base: conversation.systemPrompt, preference: preference)
        // Day 17: 注入健康上下文（最近 24h 睡眠/心率/步数）
        #if os(iOS)
        if injectHealthContext, let healthService = healthKitService, healthService.isAuthorized {
            if let summary = try? await healthService.fetchDailySummary() {
                let healthLine = "用户最近 24h：睡眠 \(String(format: "%.1f", summary.sleepHours))h，心率均值 \(String(format: "%.0f", summary.avgHeartRate))bpm，步数 \(summary.stepCount)"
                effectiveSystemPrompt = (effectiveSystemPrompt.isEmpty ? "" : effectiveSystemPrompt + "\n") + healthLine
            }
        }
        #endif

        var apiMessages: [APIMessage] = []
        if !effectiveSystemPrompt.isEmpty {
            apiMessages.append(APIMessage(role: "system", content: effectiveSystemPrompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil))
        }
        apiMessages.append(contentsOf: conversation.messages.map { $0.toAPIMessage() })

        // Day 6: 计算 query embedding（用于语义缓存查询/写入）
        // - RAG 开启时复用 RAG 的 query embedding，不重复调 embed API
        // - RAG 关闭但工具关闭时单独调一次 embed（缓存需要）
        // - 工具开启时不查缓存也不写缓存，但仍可复用 RAG embedding（无副作用）
        // 说明：RAG 与工具模式分别处理 embedding。RAG 开启时复用 RAG 的 query embedding 避免重复调 embed API；
        //       工具开启时不查不写缓存但可复用 embedding。
        var queryEmbedding: [Float] = []
        if ragEnabled {
            do {
                let (context, citations, ragQueryEmbedding) = try await ragService.buildAugmentedContext(query: text, modelContext: modelContext, apiKey: apiKey)
                if !context.isEmpty {
                    apiMessages.insert(APIMessage(role: "system", content: context, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil), at: 1)
                    currentCitations = citations
                } else {
                    currentCitations = []
                }
                queryEmbedding = ragQueryEmbedding
            } catch {
                currentCitations = []
                errorMessage = "知识库检索失败: \(error.localizedDescription)"
            }
        } else {
            currentCitations = []
            // 仅在非工具模式下需要 embedding（缓存用）；工具模式下不查不写缓存
            if !toolsEnabled {
                queryEmbedding = (try? await llmClient.embed(texts: [text], apiKey: apiKey)).flatMap { $0.first } ?? []
            }
        }

        apiMessages = limitTokens(apiMessages, max: tokenLimit)
        var loopCount = 0
        var fullResponse = ""

        // Day 6: 语义缓存查询（仅非工具模式）
        // 说明：缓存命中直接走假打字 + 收尾 return，避免触发 LLM 请求
        if !toolsEnabled, !queryEmbedding.isEmpty,
           let cached = cache.get(query: text, embedding: queryEmbedding) {
            // 缓存命中：以流式效果展示，避免突兀瞬间出现
            let chars = Array(cached)
            for piece in chars.chunked(into: 4) {
                if Task.isCancelled { return }
                streamingText += String(piece)
                try? await Task.sleep(nanoseconds: 8_000_000) // 8ms / 4 chars
            }
            fullResponse = cached
            // 跳过 ReAct 循环，直接收尾
            let assistantMsg = ChatMessage(role: "assistant", content: fullResponse)
            assistantMsg.conversation = conversation
            conversation.messages.append(assistantMsg)
            messages.append(assistantMsg)
            streamingText = ""
            isLoading = false
            try? modelContext.save()
            return
        }

        // Day 15: BFF 模式下，缓存未命中且即将调用 chat 前申请限流令牌
        // 缓存命中已在上方提前 return，故此处仅对真实 LLM 请求限流
        if bffConfig.enabled {
            do {
                try await rateLimiter.acquireChat()
            } catch {
                // 令牌耗尽：rateLimited → UI 错误条「请求过于频繁，请 X 秒后重试」
                if let llmErr = error as? LLMError, case .rateLimited(let retryAfter) = llmErr {
                    errorMessage = "请求过于频繁，请 \(Int(retryAfter)) 秒后重试"
                } else {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
                streamingText = ""
                endLiveActivity()
                return
            }
        }

        // Day 12+13: SmartRouter 决定模型名（按实际使用的 provider 映射到对应 provider 的模型名）
        // Day 16: 端侧降级到云端时，模型名映射到云端 provider 的模型
        let requestProvider = effectiveProviderForRequest()
        let effectiveModel: String
        if modelSelectionMode == "auto" {
            let routed = SmartRouter.route(input: text, toolsEnabled: toolsEnabled, hasImage: pendingImage != nil)
            // SmartRouter 输出 "deepseek-chat" / "deepseek-reasoner"，需按实际 provider 映射
            effectiveModel = mapModelName(routed, for: requestProvider)
        } else {
            // 用户手动选的具体模型名（如 "deepseek-chat"），同样按实际 provider 映射
            effectiveModel = mapModelName(modelSelectionMode, for: requestProvider)
        }
        let chatConfig = ChatConfig(
            model: effectiveModel,
            systemPrompt: conversation.systemPrompt,
            maxTokens: 2048,
            temperature: 0.7
        )
        // Day 14: 记录 LLM 请求开始时间，用于计算 latency
        let llmStartTime = Date()
        // Day 14: 发送前埋点 messageSent（provider / model / 估算输入 token 数，粗估 inputText.count / 4）
        let providerName = selectedProvider.displayName
        let modelName = effectiveModel
        let estimatedInputTokens = text.count / 4
        Task.detached { await TelemetryService.shared.track(.messageSent(provider: providerName, model: modelName, inputTokens: estimatedInputTokens)) }
        // ReAct 循环：每轮发起一次 chat 请求，若有 tool_calls 则执行工具后继续下一轮，否则结束循环
        while loopCount < maxReActLoops {
            loopCount += 1
            let stream: AsyncStream<ParsedChunk>
            if toolsEnabled {
                let tools = ToolRegistry.shared.allToolDefs
                stream = llmClient.chat(messages: apiMessages, config: chatConfig, tools: tools, apiKey: apiKey)
            } else {
                let raw = llmClient.chat(messages: apiMessages, config: chatConfig, apiKey: apiKey)
                stream = AsyncStream { cont in
                    Task {
                        for await content in raw {
                            cont.yield(ParsedChunk(content: content, toolCalls: nil))
                        }
                        cont.finish()
                    }
                }
            }
            var chunkContent = ""
            var finalToolCalls: [AccumulatedToolCall]?
            var hasUpdatedLiveActivity = false
            // Day 19: 流式 throttle——累积 chunkContent，每 100ms 最多触发一次 streamingText 更新
            // 避免 chunk 高频到达时 @Observable streamingText 频繁刷新导致 UI 抖动
            var lastStreamingUIUpdateAt: Date?
            for await chunk in stream {
                if Task.isCancelled { return }
                if let content = chunk.content {
                    chunkContent += content
                    // throttle：距上次 UI 更新 >= 100ms 才刷新 streamingText
                    let now = Date()
                    if lastStreamingUIUpdateAt == nil || now.timeIntervalSince(lastStreamingUIUpdateAt!) >= 0.1 {
                        streamingText = fullResponse + chunkContent
                        lastStreamingUIUpdateAt = now
                    }
                    // 补充 D：收到首字后更新灵动岛状态为「回复中」
                    if !hasUpdatedLiveActivity {
                        updateLiveActivity(status: "回复中")
                        hasUpdatedLiveActivity = true
                    }
                }
                if let calls = chunk.toolCalls {
                    finalToolCalls = calls
                }
            }
            // Day 19: 流式结束后立即 flush 最终文本，确保末尾内容完整展示
            streamingText = fullResponse + chunkContent
            fullResponse += chunkContent
            if let toolCalls = finalToolCalls, !toolCalls.isEmpty {
                let toolCallsData: Data? = {
                    struct StoredToolCall: Codable {
                        let id: String
                        let type: String
                        let name: String
                        let arguments: String
                    }
                    let stored = toolCalls.map { StoredToolCall(id: $0.id, type: $0.type, name: $0.name, arguments: $0.arguments) }
                    return try? JSONEncoder().encode(stored)
                }()
                let assistantMsg = ChatMessage(role: "assistant", content: chunkContent, toolCallData: toolCallsData)
                assistantMsg.conversation = conversation
                conversation.messages.append(assistantMsg)
                messages.append(assistantMsg)
                try? modelContext.save()
                var toolResults: [APIMessage] = []
                // Day 8: thought 为 chunkContent（非空时显示思维链）
                let thought = chunkContent.isEmpty ? nil : chunkContent
                for tc in toolCalls {
                    let step = ToolStep(
                        toolName: tc.name,
                        status: .running,
                        result: nil,
                        thought: thought,
                        arguments: tc.arguments,
                        loopIndex: loopCount
                    )
                    currentToolSteps.append(step)
                    let stepIdx = currentToolSteps.count - 1
                    // Day 14: 记录工具执行开始时间，用于计算 duration
                    let toolStartTime = Date()
                    do {
                        let argsData = tc.arguments.data(using: .utf8) ?? Data()
                        let args = try JSONSerialization.jsonObject(with: argsData) as? [String: Any] ?? [:]
                        // Day 8: 单工具超时保护，超时抛错不中断循环
                        // 说明：withThrowingTaskGroup + 超时 Task 抛错，第一个完成的 Task 胜出；
                        //       超时后标记 failed 继续下一轮，保证 ReAct 不因单工具卡死而中断。
                        let result = try await withThrowingTaskGroup(of: String.self) { group in
                            group.addTask {
                                try await ToolRegistry.shared.execute(name: tc.name, arguments: args)
                            }
                            group.addTask {
                                try await Task.sleep(nanoseconds: UInt64(self.toolTimeout * 1_000_000_000))
                                throw NSError(domain: "ToolTimeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "工具执行超时（\(Int(self.toolTimeout))s）"])
                            }
                            let first = try await group.next() ?? ""
                            group.cancelAll()
                            return first
                        }
                        currentToolSteps[stepIdx].status = .completed
                        currentToolSteps[stepIdx].result = result
                        // Day 14: 工具执行成功埋点
                        let toolDurationMs = Int(Date().timeIntervalSince(toolStartTime) * 1000)
                        let toolName = tc.name
                        Task.detached { await TelemetryService.shared.track(.toolCall(toolName: toolName, success: true, durationMs: toolDurationMs)) }
                        // 补充 D：工具执行成功后发本地通知
                        NotificationService.shared.sendNotification(
                            title: "工具调用成功",
                            body: "\(tc.name) 已完成：\(result)"
                        )
                        toolResults.append(APIMessage(role: "tool", content: result, images: nil, toolCallId: tc.id, toolName: tc.name, toolCalls: nil))
                        let toolMsg = ChatMessage(role: "tool", content: result, toolCallId: tc.id, toolName: tc.name)
                        toolMsg.conversation = conversation
                        conversation.messages.append(toolMsg)
                        messages.append(toolMsg)
                        try? modelContext.save()
                    } catch {
                        // Day 14: 工具执行失败埋点 + 错误埋点
                        let toolDurationMs = Int(Date().timeIntervalSince(toolStartTime) * 1000)
                        let toolName = tc.name
                        let errorType = String(describing: error)
                        let errorMsg = "工具 \(tc.name) 执行失败"
                        Task.detached { await TelemetryService.shared.track(.toolCall(toolName: toolName, success: false, durationMs: toolDurationMs)) }
                        Task.detached { await TelemetryService.shared.track(.errorOccurred(errorType: errorType, userMessage: errorMsg)) }
                        let errMsg = error.localizedDescription
                        currentToolSteps[stepIdx].status = .failed
                        currentToolSteps[stepIdx].result = errMsg
                        // Day 8: 超时/失败时也给 AI 一个 tool message，让它知道该工具失败的原因
                        toolResults.append(APIMessage(role: "tool", content: "工具执行失败: \(errMsg)", images: nil, toolCallId: tc.id, toolName: tc.name, toolCalls: nil))
                        let toolMsg = ChatMessage(role: "tool", content: "工具执行失败: \(errMsg)", toolCallId: tc.id, toolName: tc.name)
                        toolMsg.conversation = conversation
                        conversation.messages.append(toolMsg)
                        messages.append(toolMsg)
                        try? modelContext.save()
                        errorMessage = "工具 \(tc.name) 执行失败: \(errMsg)"
                    }
                }
                apiMessages = conversation.messages.map { $0.toAPIMessage() }
                continue
            } else {
                break
            }
        }
        if loopCount >= maxReActLoops && fullResponse.isEmpty {
            errorMessage = "工具调用循环超过 \(maxReActLoops) 轮，已中止"
            // Day 14: 循环超限埋点 errorOccurred
            let maxLoops = maxReActLoops
            Task.detached { await TelemetryService.shared.track(.errorOccurred(errorType: "MaxReActLoopsExceeded", userMessage: "工具调用循环超过 \(maxLoops) 轮，已中止")) }
        }
        // Day 13: 循环结束后读取 FallbackLLMProvider 的最终状态（若装饰了 fallback）
        if let fallback = llmClient as? FallbackLLMProvider {
            self.lastUsedProvider = fallback.lastUsedProvider
            self.didFallbackLastRequest = fallback.didFallback
        }
        // Day 14: 检测到 lastUsedProvider 与 selectedProvider 不一致时埋点 fallbackTriggered
        if didFallbackLastRequest {
            let fromProvider = selectedProvider.displayName
            let toProvider = lastUsedProvider?.displayName ?? "unknown"
            Task.detached { await TelemetryService.shared.track(.fallbackTriggered(from: fromProvider, to: toProvider, reason: "primary_no_output")) }
        }
        // Day 14: LLM 响应后埋点 llmResponse（latencyMs / success / 估算输出 token 数）
        let latencyMs = Int(Date().timeIntervalSince(llmStartTime) * 1000)
        let responseSuccess = !fullResponse.isEmpty
        let estimatedOutputTokens = fullResponse.count / 4
        Task.detached { await TelemetryService.shared.track(.llmResponse(latencyMs: latencyMs, success: responseSuccess, outputTokens: estimatedOutputTokens)) }
        let assistantMsg = ChatMessage(role: "assistant", content: fullResponse)
        assistantMsg.conversation = conversation
        conversation.messages.append(assistantMsg)
        messages.append(assistantMsg)
        streamingText = ""
        isLoading = false
        try? modelContext.save()

        // Day 6: 语义缓存写入（仅非工具模式且响应非空且 embedding 有效）
        // 说明：仅非工具模式且响应非空且 embedding 有效才写缓存，
        //       避免工具调用的中间结果污染缓存。
        if !toolsEnabled, !fullResponse.isEmpty, !queryEmbedding.isEmpty {
            cache.set(query: text, embedding: queryEmbedding, response: fullResponse)
        }

        // 补充 C：填充调试信息（不持久化，仅当前会话）
        let promptJSON = (try? JSONSerialization.data(withJSONObject: apiMessages.map { msg in
            ["role": msg.role, "content": msg.content]
        }, options: [.prettyPrinted])).flatMap { String(data: $0, encoding: .utf8) } ?? "无"
        lastDebugInfo = DebugInfo(
            promptJSON: promptJSON,
            apiResponse: fullResponse.isEmpty ? "无" : fullResponse,
            embeddingDimension: queryEmbedding.count,
            toolCalls: currentToolSteps.map { step in
                DebugInfo.ToolCallDebug(
                    toolName: step.toolName,
                    arguments: step.arguments,
                    result: step.result ?? ""
                )
            },
            // Day 13: 填充 provider / fallbackUsed
            provider: lastUsedProvider?.displayName,
            fallbackUsed: didFallbackLastRequest
        )

        // 补充 D：回复结束，关闭灵动岛
        endLiveActivity()
    }

    // MARK: - Day 12: 反馈闭环

    /// 提交用户对 assistant 消息的反馈，触发 RAG chunk 权重调整
    /// - Parameters:
    ///   - messageId: 被反馈的 ChatMessage.id
    ///   - isPositive: true=点赞（提权），false=踩（降权）
    ///   - citations: 该消息关联的 RAG 引用分块（来自 currentCitations）
    ///   - modelContext: SwiftData 上下文
    func submitFeedback(messageId: UUID, isPositive: Bool, citations: [DocumentChunk], modelContext: ModelContext) {
        let storage = ChatStorage(modelContext: modelContext)
        // 查询是否已有反馈记录
        if let existing = storage.fetchFeedback(messageId: messageId) {
            // 切换反馈状态：撤销旧权重应用新权重
            storage.updateFeedback(existing, isPositive: isPositive, citations: citations)
        } else {
            // 新反馈
            storage.saveFeedback(messageId: messageId, isPositive: isPositive, citations: citations)
        }
    }

    /// 便捷方法：处理用户反馈点击，更新 UI 状态并持久化
    func handleFeedback(messageId: UUID, isPositive: Bool, modelContext: ModelContext) {
        // 如果点击的是已选中的状态，则取消反馈
        if feedbackStates[messageId] == isPositive {
            feedbackStates.removeValue(forKey: messageId)
            feedbackToast = nil
            return
        }
        // 更新 UI 状态
        feedbackStates[messageId] = isPositive
        feedbackToast = isPositive ? "感谢点赞" : "感谢反馈，我们会持续改进"
        // 持久化反馈
        submitFeedback(messageId: messageId, isPositive: isPositive, citations: currentCitations, modelContext: modelContext)
        // 2 秒后自动清除提示
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.feedbackToast = nil
        }
    }

    // MARK: - 补充 D：Live Activities 灵动岛

    /// 启动灵动岛（iOS 16.1+ 可用，低版本静默降级）
    private func startLiveActivity(query: String) {
        #if os(iOS)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TimerActivityAttributes(query: query)
        let state = TimerActivityAttributes.ContentState(status: "思考中", elapsed: 0)
        do {
            liveActivity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        } catch {
            // 启动失败静默，不影响主流程
        }
        #endif
    }

    /// 更新灵动岛状态
    private func updateLiveActivity(status: String) {
        #if os(iOS)
        guard #available(iOS 16.1, *), let activity = liveActivity else { return }
        let state = TimerActivityAttributes.ContentState(status: status, elapsed: 0)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    /// 结束灵动岛
    private func endLiveActivity() {
        #if os(iOS)
        guard #available(iOS 16.1, *), let activity = liveActivity else { return }
        let state = TimerActivityAttributes.ContentState(status: "完成", elapsed: 0)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        liveActivity = nil
        #endif
    }

    /// 测试性调整：把 limitTokens 暴露为 internal 便于单测验证 tokenLimit 截断逻辑（生产侧行为不变）
    func limitTokens(_ messages: [APIMessage], max: Int) -> [APIMessage] {
        var total = 0
        var result: [APIMessage] = []
        for msg in messages.reversed() {
            let tokens = msg.content.estimatedTokens
            if total + tokens > max { break }
            result.insert(msg, at: 0)
            total += tokens
        }
        return result
    }

    /// 测试性调整：把 systemPrompt + 用户偏好拼接逻辑提取为 internal 方法便于单测
    /// 生产侧行为不变：与原 processMessage 中内联实现等价
    func buildEffectiveSystemPrompt(base: String, preference: UserPreference) -> String {
        var prefParts: [String] = []
        if !preference.preferredTone.isEmpty && preference.preferredTone != "默认" {
            prefParts.append("语气：\(preference.preferredTone)")
        }
        if !preference.preferredTools.isEmpty {
            prefParts.append("偏好工具：\(preference.preferredTools.joined(separator: "、"))")
        }
        if !preference.customFact.isEmpty {
            prefParts.append("自定义事实：\(preference.customFact)")
        }
        guard !prefParts.isEmpty else { return base }
        return (base.isEmpty ? "" : base + "\n") + "【用户偏好】" + prefParts.joined(separator: "；")
    }
}
