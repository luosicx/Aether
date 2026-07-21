import Foundation
import SwiftData
import Observation
import AetherFoundation
import AetherServices
import AetherUI
import os

/// 非隔离通知观察者持有者，deinit 中安全移除观察者。P1-5: NSLock 包裹 token（NSObjectProtocol 非 Sendable）。
private final class ErrorObserver: @unchecked Sendable {
    private var _token: NSObjectProtocol?
    private let lock = NSLock()

    var token: NSObjectProtocol? {
        get { lock.lock(); defer { lock.unlock() }; return _token }
        set { lock.lock(); defer { lock.unlock() }; _token = newValue }
    }
}

/// 核心 ViewModel，@Observable + @MainActor 隔离。P2-6 已抽取 10 个 Coordinator。
@Observable
@MainActor
final class ChatViewModel {
    // MARK: - @Observable 状态属性（View 层通过 $vm.xxx 绑定）
    var messages: [ChatMessage] = []                    // 当前会话消息列表
    var inputText = ""                                  // 输入框文本
    var isLoading = false                               // 是否正在等待/流式输出
    var streamingText = ""                              // 当前流式输出文本（实时更新）
    var errorMessage: String?                           // 错误消息（nil 表示无错误）
    var currentToolSteps: [ToolStep] = []               // 当前 ReAct 循环的工具步骤列表
    var ragEnabled = false                              // Day 3: 是否在发送消息前检索本地知识库
    var toolsEnabled = false                            // Day 4: 是否启用工具调用进入 ReAct 循环
    var tokenLimit = 4000                               // 上下文 token 上限，超出时从尾部截断
    var selectedModel: String = APIConfig.defaultModel  // 当前选中的 LLM 模型名
    var modelSelectionMode: String = "auto"             // Day 12: "auto"=智能路由 / "deepseek-chat" / "deepseek-reasoner"
    var selectedProvider: ModelProvider = .deepseek     // Day 13: 当前选中的 LLM 供应商
    var fallbackProvider: ModelProvider?                // Day 13: 备用供应商（nil=不降级；非 nil 时用 FallbackLLMProvider 装饰）
    var bffConfig: BFFConfig = .default                 // Day 15: BFF 代理配置（启用后请求经服务端中转）
    var onDeviceConfig: OnDeviceConfig = .default       // Day 16: 端侧推理配置（开关 / 模型路径 / 采样参数）
    private(set) var currentNetworkStatus: NetworkStatus = .online  // P2-6 Task 6: NetworkFallbackCoordinator 写入
    private let rateLimiter = RateLimiter()             // Day 15: 客户端令牌桶限流器（BFF 模式下 chat 前申请令牌）
    private(set) var lastUsedProvider: ModelProvider?   // Day 13: 最近一次请求实际命中的 provider
    private(set) var didFallbackLastRequest: Bool = false  // Day 13: 最近一次请求是否触发了降级
    private let injectedClientUsed: Bool                // Day 13: 标记 init 时是否注入了测试 client
    var currentCitations: [DocumentChunk] = []          // 当前 RAG 检索的引用分块列表
    var isRecording = false                             // Day 5: 是否正在录音
    var speakingMessageId: UUID?                        // Day 5: 正在朗读的消息 ID
    var pendingImage: Data?                             // 补充 A: 待发送的图片
    var lastDebugInfo: DebugInfo?                       // 补充 C: 最近一次请求的调试信息
    var injectHealthContext: Bool = false               // Day 17: 是否在发送消息时注入健康上下文
    #if os(iOS)
    var healthKitService: HealthKitService?             // Day 17: HealthKit 服务（默认 nil，由设置页注入）
    #endif
    var feedbackStates: [UUID: Bool] = [:]              // P2-6 Task 3: FeedbackCoordinator 镜像同步，true=赞 / false=踩
    var feedbackToast: String?                          // 反馈操作后的提示文本（如"感谢反馈"）
    var ttsConfig: TTSConfig = .load()                  // TTS 朗读配置（音色/语速/音调/音量）
    var contextWindowManager: ContextWindowManager?     // Task 7: 上下文窗口管理器（nil 时不压缩历史消息）
    var semanticMemoryStore: SemanticMemoryStore?       // Task 8: 语义记忆存储（nil 时不注入相关记忆到 systemPrompt）
    var conversationRepo: ConversationRepository?       // Task 3.1: 会话仓储（nil 时降级到 ModelContext 直查）
    var messageRepo: MessageRepository?                 // Task 3.1: 消息仓储
    var showInjectionWarning: Bool = false              // P2-6 Task 9: InjectionGuard 写入，弹窗显示状态
    var injectionWarningMessage: String = ""            // Task 7: 提示注入检测弹窗提示文案
    @ObservationIgnored
    var pendingInjectionDecision: InjectionDecisionHandler?  // View 调用路由到 InjectionGuard.proceed()/cancel()
    var pendingWatchMessage: String?                    // Task 4: Watch 发来的快速对话消息（非 nil 时 ChatView 写入并发送）

    // 测试性调整：client / cache 暴露为 internal 支持注入（默认 DeepSeekClient() / SemanticCache() 兜底）
    let client: LLMProvider
    let cache: SemanticCache
    let voiceService = VoiceService()                   // 语音服务（录音识别 + 朗读），SettingsView 复用此实例避免音频 daemon 争用
    // MARK: - P2-6 Coordinators（隐式解包可选以便 init 末尾捕获 self 构造）
    @ObservationIgnored private var voiceCoordinator: VoiceCoordinator!           // Task 1: STT/TTS 协调器
    @ObservationIgnored private var feedbackCoordinator: FeedbackCoordinator!     // Task 3: 反馈闭环协调器
    @ObservationIgnored private var quickChatCoordinator: WatchQuickChatCoordinator!  // Task 4: Watch 快速对话消息桥接
    @ObservationIgnored private var networkFallbackCoordinator: NetworkFallbackCoordinator!  // Task 6: 网络监听 + 端侧切换 + Provider 工厂
    @ObservationIgnored private var retrievalCoordinator: RetrievalCoordinator!   // Task 7: RAG 检索 + 语义缓存 + embedding 降级
    @ObservationIgnored private let promptBuilder = PromptBuilder()               // Task 8: systemPrompt 构建（纯值类型 struct）
    @ObservationIgnored private var injectionGuard: InjectionGuard!               // Task 9: 提示注入检测弹窗
    @ObservationIgnored private var toolExecutionCoordinator: ToolExecutionCoordinator!  // Task 10: ReAct 工具执行循环
    #if os(iOS)
    private let liveActivityCoordinator: LiveActivityCoordinator                  // Task 2: iOS 灵动岛全生命周期
    @ObservationIgnored private var healthContextInjector: HealthContextInjector!  // Task 5: iOS HealthKit 上下文注入
    #endif
    private var streamingTask: Task<Void, Never>?      // 当前流式输出 Task（可取消）
    @ObservationIgnored private(set) var state: ChatState = .idle  // Task 6: 状态机当前状态
    private let maxReActLoops = 5                       // ReAct 循环最大轮次
    private let toolTimeout: TimeInterval = 15          // Day 8: 单工具执行超时（秒），构造器注入 ToolExecutionCoordinator
    nonisolated private let errorObserver = ErrorObserver()  // Day 10: 通知中心观察者，deinit 中移除

    /// Task 6: processMessage 状态机枚举（Sendable，便于跨 actor 传递状态快照）。
    enum ChatState: Sendable {
        case idle           // 空闲
        case preparing      // 准备中（UITEST 短路 / 构造 LLMProvider / 读取 apiKey / 构建 systemPrompt 与 apiMessages）
        case ragRetrieving  // RAG 知识库检索中
        case cacheChecking  // 语义缓存检查（含 BFF 限流 / API Key 预检 / SmartRouter 路由）
        case llmStreaming   // LLM 流式输出中
        case toolCalling    // ReAct 工具调用循环中
        case finishing      // 收尾（持久化 / LiveActivity / 朗读 / telemetry）
        case error          // 错误状态
    }

    /// Task 6: processMessage 状态机内部上下文，承载 handle* 方法间共享的可变状态（值类型，通过 inout 传递）。
    private struct ProcessContext {
        let text: String                    // 用户输入文本
        let conversation: Conversation      // 当前会话
        let modelContext: ModelContext      // SwiftData 上下文
        var llmClient: LLMProvider          // LLM 客户端（preparing 构造）
        var apiKey: String                  // API Key（preparing 读取）
        var provider: ModelProvider         // 进入流程时的 selectedProvider 快照
        var apiMessages: [APIMessage]       // 待发送给 LLM 的消息序列
        var queryEmbedding: [Float]         // 查询向量（RAG/缓存读写使用）
        var loopCount: Int = 0              // ReAct 循环当前轮次（从 1 开始）
        var fullResponse: String = ""       // 累积的完整回复文本
        var chatConfig: ChatConfig?         // LLM 请求配置（cacheChecking 构造）
        var llmStartTime: Date?             // LLM 请求开始时间（cacheChecking 记录，finishing 计算 latency）
        var lastChunkContent: String = ""   // 上一轮流式输出累积的 chunk 文本
        var finalToolCalls: [AccumulatedToolCall]?  // 上一轮流式输出解析出的工具调用
    }

    // P2-6 Task 10: ToolStep / ToolStepStatus typealias 兼容测试代码引用。
    typealias ToolStep = ToolExecutionCoordinator.ToolStep
    typealias ToolStepStatus = ToolExecutionCoordinator.ToolStepStatus

    /// 初始化。client / cache 可注入为测试可替换，生产默认 DeepSeekClient() / SemanticCache() 兜底。
    init(client: LLMProvider? = nil, cache: SemanticCache? = nil) {
        self.client = client ?? DeepSeekClient()
        self.cache = cache ?? SemanticCache()
        self.injectedClientUsed = client != nil
        #if os(iOS)
        self.liveActivityCoordinator = LiveActivityCoordinator()
        healthContextInjector = HealthContextInjector(
            healthKitServiceProvider: { [weak self] in self?.healthKitService },
            injectHealthContextProvider: { [weak self] in self?.injectHealthContext ?? false }
        )
        #endif
        feedbackCoordinator = FeedbackCoordinator(
            citationsProvider: { [weak self] in self?.currentCitations ?? [] },
            onFeedbackStatesChange: { [weak self] value in self?.feedbackStates = value },
            onFeedbackToastChange: { [weak self] value in self?.feedbackToast = value }
        )
        // errorObserver: 后台 OperationQueue 处理 LLM 错误，避免主线程同步回调
        errorObserver.token = NotificationCenter.default.addObserver(
            forName: .llmErrorOccurred, object: nil, queue: OperationQueue()
        ) { [weak self] notification in
            guard let self = self else { return }
            let llmErr = notification.userInfo?["error"] as? LLMError  // 优先 LLMError，回退兼容 String message
            let userMsg: String? = llmErr?.userMessage ?? (notification.userInfo?["message"] as? String)
            guard let msg = userMsg else { return }
            let errorType = llmErr.map { String(describing: $0) } ?? "LLMError"
            CrashReportService.shared.reportException(llmErr ?? NSError(domain: "LLMError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
            Task.detached { await TelemetryService.shared.track(.errorOccurred(errorType: errorType, userMessage: msg)) }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.errorMessage != msg { self.errorMessage = msg }
                self.isLoading = false
                self.streamingText = ""
            }
        }
        voiceCoordinator = VoiceCoordinator(
            voiceService: voiceService,
            ttsConfigProvider: { [weak self] in self?.ttsConfig ?? .defaultValue },
            isRecordingProvider: { [weak self] in self?.isRecording ?? false },
            onIsRecordingChange: { [weak self] value in self?.isRecording = value },
            onSpeakingMessageIdChange: { [weak self] value in self?.speakingMessageId = value },
            onInputTextChange: { [weak self] value in self?.inputText = value },
            onErrorMessageChange: { [weak self] value in self?.errorMessage = value }
        )
        networkFallbackCoordinator = NetworkFallbackCoordinator(
            selectedProviderProvider: { [weak self] in self?.selectedProvider ?? .deepseek },
            onSelectedProviderChange: { [weak self] value in self?.selectedProvider = value },
            onCurrentNetworkStatusChange: { [weak self] value in self?.currentNetworkStatus = value },
            onLastUsedProviderChange: { [weak self] value in self?.lastUsedProvider = value },
            onDidFallbackLastRequestChange: { [weak self] value in self?.didFallbackLastRequest = value }
        )
        retrievalCoordinator = RetrievalCoordinator(
            cache: self.cache,
            selectedProviderProvider: { [weak self] in self?.selectedProvider ?? .deepseek },
            ragEnabledProvider: { [weak self] in self?.ragEnabled ?? false },
            toolsEnabledProvider: { [weak self] in self?.toolsEnabled ?? false },
            onCurrentCitationsChange: { [weak self] value in self?.currentCitations = value },
            onErrorMessageChange: { [weak self] value in self?.errorMessage = value }
        )
        injectionGuard = InjectionGuard(
            onShowInjectionWarningChange: { [weak self] value in self?.showInjectionWarning = value },
            onInjectionWarningMessageChange: { [weak self] value in self?.injectionWarningMessage = value },
            onPendingInjectionDecisionChange: { [weak self] value in self?.pendingInjectionDecision = value }
        )
        toolExecutionCoordinator = ToolExecutionCoordinator(
            toolTimeout: toolTimeout,
            onToolStepAppend: { [weak self] step in self?.currentToolSteps.append(step) },
            onToolStepUpdate: { [weak self] idx, status, result in
                guard let self = self, idx >= 0, idx < self.currentToolSteps.count else { return }
                self.currentToolSteps[idx].status = status
                self.currentToolSteps[idx].result = result
            },
            onMessageAppend: { [weak self] msg in self?.messages.append(msg) },
            onErrorMessageChange: { [weak self] value in self?.errorMessage = value }
        )
        if onDeviceConfig.autoSwitchOnNetworkLoss {
            startNetworkMonitoring()
        }
        quickChatCoordinator = WatchQuickChatCoordinator { [weak self] msg in
            self?.pendingWatchMessage = msg
        }
    }

    /// 释放 errorObserver 避免泄漏。各 Coordinator 自身 deinit 清理资源（如 quickChatCoordinator 移除 `.wcQuickChatReceived` 观察者）。
    deinit {
        if let observer = errorObserver.token {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Day 16: 端侧推理 / 网络监听（转发至 NetworkFallbackCoordinator）

    /// 启动网络状态监听。断网切端侧推理，联网切回原 provider。
    private func startNetworkMonitoring() { networkFallbackCoordinator.startNetworkMonitoring() }

    /// 切换到端侧推理，保存当前 provider 供联网后恢复。
    func switchToOnDevice() { networkFallbackCoordinator.switchToOnDevice() }

    /// 切回原 provider（联网后恢复）。仅当处于端侧推理且有保存的原 provider 时生效。
    func switchToOriginalProvider() { networkFallbackCoordinator.switchToOriginalProvider() }

    /// Day 13+16: 按 selectedProvider / fallbackProvider 构造 LLMProvider。端侧推理不支持工具调用，需工具且网络可用时降级到云端。
    private func makeLLMProvider() -> LLMProvider {
        let effectiveProvider = networkFallbackCoordinator.effectiveProviderForRequest(
            selectedProvider: selectedProvider, toolsEnabled: toolsEnabled
        )
        return networkFallbackCoordinator.makeLLMProvider(
            selectedProvider: effectiveProvider,
            fallbackProvider: fallbackProvider,
            bffConfig: bffConfig,
            onDeviceConfig: onDeviceConfig,
            injectedClient: injectedClientUsed ? client : nil
        )
    }

    /// Day 16: 计算本次请求实际使用的 provider（端侧不支持工具时降级到云端 fallback）。
    private func effectiveProviderForRequest() -> ModelProvider {
        networkFallbackCoordinator.effectiveProviderForRequest(
            selectedProvider: selectedProvider, toolsEnabled: toolsEnabled
        )
    }

    /// Day 13: SmartRouter 模型名映射（"deepseek-chat"→defaultChatModel / "deepseek-reasoner"→defaultReasonerModel / 其他→原值）。
    private func mapModelName(_ name: String, for provider: ModelProvider) -> String {
        networkFallbackCoordinator.mapModelName(name, for: provider)
    }

    // MARK: - Day 5 语音（转发至 VoiceCoordinator）

    /// 切换语音输入。首次调用请求权限，授权后开始/停止录音；识别结果实时写入 inputText。
    func toggleVoiceInput() { voiceCoordinator.toggleVoiceInput() }

    /// 切换语音朗读。点击同一条消息则停止；点击另一条则切换。
    func toggleSpeak(messageId: UUID, content: String) {
        voiceCoordinator.toggleSpeak(messageId: messageId, content: content)
    }

    /// 切换到指定会话：清理流式状态、加载该会话消息
    func switchTo(conversation: Conversation) {
        streamingTask?.cancel()
        streamingTask = nil
        streamingText = ""
        isLoading = false
        currentToolSteps = []
        toolExecutionCoordinator.resetStepCounter()  // 同步重置 step 计数器，保证 stepIdx 与 currentToolSteps 索引一致
        currentCitations = []
        errorMessage = nil
        inputText = ""
        messages = conversation.messages
    }

    /// 发送当前 inputText。空 input 守卫不触发；Task 7 + P2-6 Task 9: 注入检测转发至 InjectionGuard。
    func sendMessage(in conversation: Conversation, modelContext: ModelContext) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if injectionGuard.detect(text: inputText) {
            injectionGuard.setDecisionHandler { [weak self] shouldContinue in
                guard let self = self else { return }
                if shouldContinue {
                    self.sendMessageConfirmed(content: inputText, in: conversation, modelContext: modelContext, injectionChecked: true)
                }
            }
            return
        }

        sendMessageConfirmed(content: inputText, in: conversation, modelContext: modelContext, injectionChecked: false)
    }

    /// sendMessage 确认后的实际发送逻辑。
    private func sendMessageConfirmed(content: String, in conversation: Conversation, modelContext: ModelContext, injectionChecked: Bool) {
        let userMessage = ChatMessage(role: "user", content: content)
        userMessage.injectionChecked = injectionChecked
        if let imageData = pendingImage {  // 补充 A：附加待发送图片
            userMessage.attachedImage = imageData
            pendingImage = nil
        }
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        messages.append(userMessage)
        let userInput = content
        inputText = ""
        isLoading = true
        streamingText = ""
        currentToolSteps = []
        toolExecutionCoordinator.resetStepCounter()  // 重置 step 计数器保证 stepIdx 与 currentToolSteps 索引一致
        startLiveActivity(query: userInput)
        do { try modelContext.save() } catch { Logger.chat.error("持久化用户消息失败: \(error.localizedDescription, privacy: .public)") }  // 立即持久化防丢失
        streamingTask = Task { [weak self] in
            await self?.processMessage(userInput, conversation: conversation, modelContext: modelContext)
        }
    }

    /// 重新提问：将旧问题内容填入输入框并触发发送
    func resendMessage(content: String, in conversation: Conversation, modelContext: ModelContext) {
        inputText = content
        sendMessage(in: conversation, modelContext: modelContext)
    }

    /// Task 23.2: 重新生成 AI 回复。找到 AI 消息前序最近一条 user 消息，删除该 AI 消息后用同一 user 输入重新发送。
    func regenerateResponse(assistantMessage: ChatMessage, in conversation: Conversation, modelContext: ModelContext) {
        guard assistantMessage.role == "assistant" else { return }
        guard let assistantIndex = conversation.messages.firstIndex(where: { $0.id == assistantMessage.id }) else { return }
        let userMessagesBefore = conversation.messages[..<assistantIndex].filter { $0.role == "user" }
        guard let lastUser = userMessagesBefore.last else { return }
        let userInput = lastUser.content
        conversation.messages.remove(at: assistantIndex)
        messages.removeAll { $0.id == assistantMessage.id }
        // 不删除 modelContext 中实体避免破坏 index；sendMessage 会重新 save 覆盖状态
        do { try modelContext.save() } catch { Logger.chat.error("重新生成-删除消息后保存失败: \(error.localizedDescription, privacy: .public)") }
        inputText = userInput
        sendMessage(in: conversation, modelContext: modelContext)
    }

    /// Task 23.2: 从指定消息处分叉——创建新会话，复制到该消息为止的所有消息（含该消息）。nil 表示分叉失败。
    @discardableResult
    func branch(from fromMessage: ChatMessage, in conversation: Conversation, modelContext: ModelContext) -> Conversation? {
        let storage = ChatStorage(modelContext: modelContext)
        do {
            return try storage.forkConversation(from: conversation, at: fromMessage.id)  // Task 21: 设置 parentConversationID / parentMessageID 复制字段
        } catch {
            Logger.chat.error("对话分叉失败 (fromMessageId=\(fromMessage.id, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Task 6: 消息处理主流程（状态机编排）：preparing → ragRetrieving → cacheChecking → (llmStreaming ↔ toolCalling)* → finishing。
    func processMessage(_ text: String, conversation: Conversation, modelContext: ModelContext) async {
        state = .preparing
        guard var ctx = await handlePreparing(text: text, conversation: conversation, modelContext: modelContext) else {
            state = .idle
            return
        }

        state = .ragRetrieving
        await handleRAGRetrieving(&ctx)

        state = .cacheChecking
        let shouldProceed = await handleCacheChecking(&ctx)
        guard shouldProceed else {
            state = .idle
            return
        }

        // ReAct 循环：llmStreaming ↔ toolCalling 交替，无 tool_calls 时跳出
        while ctx.loopCount < maxReActLoops {
            ctx.loopCount += 1
            state = .llmStreaming
            let notCancelled = await handleLLMStreaming(&ctx)
            guard notCancelled else {
                state = .idle
                return
            }
            guard let toolCalls = ctx.finalToolCalls, !toolCalls.isEmpty else { break }
            state = .toolCalling
            await handleToolCalling(&ctx, toolCalls: toolCalls)
        }

        state = .finishing
        await handleFinishing(&ctx)
        state = .idle
    }

    // MARK: - Task 6 状态机 handler

    /// SubTask 6.2: 准备阶段——UITEST 短路、构造 LLMProvider、读取 apiKey、构建 systemPrompt（偏好/健康/语义记忆）与 apiMessages、上下文压缩。返回 nil 表示 UITEST 短路已自行收尾。
    private func handlePreparing(text: String, conversation: Conversation, modelContext: ModelContext) async -> ProcessContext? {
        // UITEST_DISABLE_NETWORK: 短路 HTTP/RAG/Tool，注入桩回复复用缓存命中的假打字路径驱动 UI 状态机
        if ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_NETWORK") {
            let stubReply = String(format: NSLocalizedString("（UIT 测试模式）已收到：%@", comment: ""), text)
            isLoading = true
            streamingText = ""
            for piece in Array(stubReply).chunked(into: 4) {
                if Task.isCancelled { return nil }
                streamingText += String(piece)
                try? await Task.sleep(nanoseconds: 8_000_000) // 8ms / 4 chars
            }
            let assistantMsg = ChatMessage(role: "assistant", content: stubReply)
            assistantMsg.conversation = conversation
            conversation.messages.append(assistantMsg)
            messages.append(assistantMsg)
            streamingText = ""
            isLoading = false
            do { try modelContext.save() } catch { Logger.chat.error("UITest 桩回复保存失败: \(error.localizedDescription, privacy: .public)") }
            endLiveActivity()
            return nil
        }

        // UITEST_FORCE_LLM_ERROR: 强制注入 LLM 错误，驱动 ErrorBanner 出现
        if ProcessInfo.processInfo.arguments.contains("UITEST_FORCE_LLM_ERROR") {
            errorMessage = "请先在设置中配置 API Key"
            isLoading = false
            streamingText = ""
            endLiveActivity()
            return nil
        }

        // Day 13: 用工厂构造 LLMProvider；通过 coordinator 同步 lastUsedProvider / didFallbackLastRequest
        let llmClient = makeLLMProvider()
        networkFallbackCoordinator.updateLastUsedProvider(effectiveProviderForRequest())
        networkFallbackCoordinator.updateDidFallbackLastRequest(false)

        // 后台线程读取 apiKey 避免主线程阻塞
        let provider = self.selectedProvider
        let apiKey = await Task.detached(priority: .userInitiated) { KeychainManager.shared.getAPIKey(for: provider) ?? "" }.value

        // 注入用户偏好到 systemPrompt 末尾
        let preference = ChatStorage(modelContext: modelContext).fetchPreference()
        var effectiveSystemPrompt = buildEffectiveSystemPrompt(base: conversation.systemPrompt, preference: preference)
        #if os(iOS)  // Day 17 + P2-6 Task 5: iOS 注入健康上下文片段（macOS 编译时排除）
        let healthSnippet = await healthContextInjector.buildHealthContextSnippet()
        if !healthSnippet.isEmpty {
            effectiveSystemPrompt = (effectiveSystemPrompt.isEmpty ? "" : effectiveSystemPrompt + "\n") + healthSnippet
        }
        #endif

        // Task 8: 注入语义记忆检索（可选，semanticMemoryStore 为 nil 时跳过）
        if let memoryStore = semanticMemoryStore {
            let memories: [Memory]
            do {
                memories = try await memoryStore.retrieveRelevantMemories(query: text)
            } catch {
                Logger.chat.warning("retrieveRelevantMemories 失败，已降级为空数组：\(error.localizedDescription, privacy: .public)")
                memories = []
            }
            let memoryText = memoryStore.formatMemoriesForPrompt(memories)
            if !memoryText.isEmpty {
                effectiveSystemPrompt = (effectiveSystemPrompt.isEmpty ? "" : effectiveSystemPrompt + "\n") + memoryText
            }
        }

        var apiMessages: [APIMessage] = []
        if !effectiveSystemPrompt.isEmpty {
            apiMessages.append(APIMessage(role: "system", content: effectiveSystemPrompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil))
        }
        // Task 7: 上下文压缩（可选，contextWindowManager 为 nil 时跳过）
        let conversationMessages: [ChatMessage]
        if let contextManager = contextWindowManager {
            do {
                conversationMessages = try await contextManager.compress(messages: conversation.messages, maxTokens: tokenLimit)
            } catch {
                Logger.chat.warning("contextManager.compress 失败，已降级为原始消息：\(error.localizedDescription, privacy: .public)")
                conversationMessages = conversation.messages
            }
        } else {
            conversationMessages = conversation.messages
        }
        apiMessages.append(contentsOf: conversationMessages.map { $0.toAPIMessage() })

        return ProcessContext(text: text, conversation: conversation, modelContext: modelContext, llmClient: llmClient, apiKey: apiKey, provider: provider, apiMessages: apiMessages, queryEmbedding: [])
    }

    /// SubTask 6.3 + P2-6 Task 7: RAG 检索阶段（转发至 RetrievalCoordinator）。开启则注入 systemPrompt；关闭则按需计算 query embedding（仅非工具模式，缓存用）。
    private func handleRAGRetrieving(_ ctx: inout ProcessContext) async {
        let (ragContext, queryEmbedding) = await retrievalCoordinator.handleRAGRetrieving(
            text: ctx.text,
            modelContext: ctx.modelContext,
            llmClient: ctx.llmClient,
            apiKey: ctx.apiKey
        )
        // 仅当 RAG 检索到非空上下文时插入 system APIMessage
        if !ragContext.isEmpty {
            ctx.apiMessages.insert(APIMessage(role: "system", content: ragContext, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil), at: 1)
        }
        ctx.queryEmbedding = queryEmbedding
    }

    /// SubTask 6.4: 缓存检查阶段——limitTokens 截断、语义缓存命中则假打字收尾、BFF 限流 / API Key 预检、SmartRouter 路由与 chatConfig 构造、请求前埋点。返回 true 继续 LLM 流式；false 表示已自行收尾。
    private func handleCacheChecking(_ ctx: inout ProcessContext) async -> Bool {
        ctx.apiMessages = limitTokens(ctx.apiMessages, max: tokenLimit)

        // Day 6 + P2-6 Task 7: 语义缓存查询（仅非工具模式）。缓存命中走假打字 + 收尾 return，避免触发 LLM 请求
        if let cached = retrievalCoordinator.checkCache(query: ctx.text, embedding: ctx.queryEmbedding) {
            for piece in Array(cached).chunked(into: 4) {
                if Task.isCancelled { return false }
                streamingText += String(piece)
                try? await Task.sleep(nanoseconds: 8_000_000) // 8ms / 4 chars
            }
            ctx.fullResponse = cached
            let assistantMsg = ChatMessage(role: "assistant", content: ctx.fullResponse)
            assistantMsg.conversation = ctx.conversation
            ctx.conversation.messages.append(assistantMsg)
            messages.append(assistantMsg)
            streamingText = ""
            isLoading = false
            do { try ctx.modelContext.save() } catch { Logger.chat.error("缓存命中回复保存失败: \(error.localizedDescription, privacy: .public)") }
            return false
        }

        // Day 15: BFF 模式下，缓存未命中且即将调用 chat 前申请限流令牌
        if bffConfig.enabled {
            do {
                try await rateLimiter.acquireChat()
            } catch {
                // 令牌耗尽：rateLimited → UI 错误条「请求过于频繁，请 X 秒后重试」
                if let llmErr = error as? LLMError, case .rateLimited(let retryAfter) = llmErr {
                    errorMessage = String(format: NSLocalizedString("请求过于频繁，请 %d 秒后重试", comment: ""), Int(retryAfter))
                } else {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
                streamingText = ""
                endLiveActivity()
                return false
            }
        } else if ctx.provider != .onDevice, ctx.apiKey.isEmpty {
            // API Key 空值预检（缓存未命中、非端侧、非 BFF 模式时）
            errorMessage = LLMError.apiKeyMissing.userMessage
            isLoading = false
            streamingText = ""
            endLiveActivity()
            return false
        }

        // Day 12+13+16: SmartRouter 决定模型名，按实际 provider 映射（端侧降级到云端时映射到云端 provider 的模型）
        let requestProvider = effectiveProviderForRequest()
        let effectiveModel: String
        if modelSelectionMode == "auto" {
            let routed = SmartRouter.route(input: ctx.text, toolsEnabled: toolsEnabled, hasImage: pendingImage != nil)
            effectiveModel = mapModelName(routed, for: requestProvider)
        } else {
            effectiveModel = mapModelName(modelSelectionMode, for: requestProvider)
        }
        let chatConfig = ChatConfig(
            model: effectiveModel,
            systemPrompt: ctx.conversation.systemPrompt,
            maxTokens: 2048,
            temperature: 0.7
        )
        // Day 14: 记录 LLM 请求开始时间 + 发送前埋点 messageSent（粗估 inputText.count / 4）
        let llmStartTime = Date()
        let providerName = selectedProvider.displayName
        let modelName = effectiveModel
        let estimatedInputTokens = ctx.text.count / 4
        Task.detached { await TelemetryService.shared.track(.messageSent(provider: providerName, model: modelName, inputTokens: estimatedInputTokens)) }

        ctx.chatConfig = chatConfig
        ctx.llmStartTime = llmStartTime
        return true
    }

    /// SubTask 6.5: LLM 流式输出阶段——构造 chat 请求流（工具/纯文本两种模式）、累积 chunkContent（100ms throttle）、更新灵动岛、解析 finalToolCalls。返回 false 表示 Task 已取消。
    private func handleLLMStreaming(_ ctx: inout ProcessContext) async -> Bool {
        guard let chatConfig = ctx.chatConfig else { return true }
        let stream: AsyncStream<ParsedChunk>
        if toolsEnabled {
            let tools = ToolRegistry.shared.availableToolDefs
            stream = ctx.llmClient.chat(messages: ctx.apiMessages, config: chatConfig, tools: tools, apiKey: ctx.apiKey)
        } else {
            let raw = ctx.llmClient.chat(messages: ctx.apiMessages, config: chatConfig, apiKey: ctx.apiKey)
            stream = AsyncStream { cont in
                Task {
                    for await content in raw { cont.yield(ParsedChunk(content: content, toolCalls: nil)) }
                    cont.finish()
                }
            }
        }
        var chunkContent = ""
        var finalToolCalls: [AccumulatedToolCall]?
        var hasUpdatedLiveActivity = false
        var lastStreamingUIUpdateAt: Date?  // Day 19: 流式 throttle，每 100ms 最多刷新一次避免 UI 抖动
        for await chunk in stream {
            if Task.isCancelled { return false }
            if let content = chunk.content {
                chunkContent += content
                let now = Date()
                if lastStreamingUIUpdateAt.map { now.timeIntervalSince($0) >= 0.1 } ?? true {
                    streamingText = ctx.fullResponse + chunkContent
                    lastStreamingUIUpdateAt = now
                }
                if !hasUpdatedLiveActivity {  // 收到首字后更新灵动岛状态为「回复中」
                    updateLiveActivity(status: "回复中")
                    hasUpdatedLiveActivity = true
                }
            }
            if let calls = chunk.toolCalls { finalToolCalls = calls }
        }
        streamingText = ctx.fullResponse + chunkContent  // 流式结束后立即 flush 最终文本
        ctx.fullResponse += chunkContent
        ctx.lastChunkContent = chunkContent
        ctx.finalToolCalls = finalToolCalls
        return true
    }

    /// SubTask 6.6 → P2-6 Task 10: ReAct 工具调用阶段（转发至 ToolExecutionCoordinator.handle）。行为零回归：原 handleToolCalling 实现已 1:1 迁移。
    private func handleToolCalling(_ ctx: inout ProcessContext, toolCalls: [AccumulatedToolCall]) async {
        ctx.apiMessages = await toolExecutionCoordinator.handle(
            toolCalls: toolCalls,
            lastChunkContent: ctx.lastChunkContent,
            loopCount: ctx.loopCount,
            conversation: ctx.conversation,
            modelContext: ctx.modelContext
        )
    }

    /// SubTask 6.7: 收尾阶段——ReAct 超限检查、FallbackLLMProvider 状态读取、埋点（fallbackTriggered / llmResponse）、持久化最终助手消息、语义缓存写入、DebugInfo 填充、关闭灵动岛。
    private func handleFinishing(_ ctx: inout ProcessContext) async {
        if ctx.loopCount >= maxReActLoops, ctx.fullResponse.isEmpty {  // ReAct 循环超限：所有轮次均有 tool_calls 且无最终文本输出
            errorMessage = String(format: NSLocalizedString("工具调用循环超过 %d 轮，已中止", comment: ""), maxReActLoops)
            let maxLoops = maxReActLoops
            Task.detached { await TelemetryService.shared.track(.errorOccurred(errorType: "MaxReActLoopsExceeded", userMessage: String(format: NSLocalizedString("工具调用循环超过 %d 轮，已中止", comment: ""), maxLoops))) }
        }
        if let fallback = ctx.llmClient as? FallbackLLMProvider {  // Day 13: 读取 FallbackLLMProvider 最终状态同步 @Observable 属性
            networkFallbackCoordinator.updateLastUsedProvider(fallback.lastUsedProvider)
            networkFallbackCoordinator.updateDidFallbackLastRequest(fallback.didFallback)
        }
        if didFallbackLastRequest {  // Day 14: fallback 触发埋点
            let fromProvider = selectedProvider.displayName
            let toProvider = lastUsedProvider?.displayName ?? "unknown"
            Task.detached { await TelemetryService.shared.track(.fallbackTriggered(from: fromProvider, to: toProvider, reason: "primary_no_output")) }
        }
        let latencyMs = ctx.llmStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0  // Day 14: LLM 响应埋点（latencyMs / success / 估算输出 token 数）
        Task.detached { await TelemetryService.shared.track(.llmResponse(latencyMs: latencyMs, success: !ctx.fullResponse.isEmpty, outputTokens: ctx.fullResponse.count / 4)) }
        let assistantMsg = ChatMessage(role: "assistant", content: ctx.fullResponse)
        assistantMsg.conversation = ctx.conversation
        ctx.conversation.messages.append(assistantMsg)
        messages.append(assistantMsg)
        streamingText = ""
        isLoading = false
        do { try ctx.modelContext.save() } catch { Logger.chat.error("最终助手回复保存失败: \(error.localizedDescription, privacy: .public)") }

        retrievalCoordinator.writeCache(query: ctx.text, embedding: ctx.queryEmbedding, response: ctx.fullResponse)  // Day 6 + P2-6 Task 7: 语义缓存写入

        let promptJSON = (try? JSONSerialization.data(withJSONObject: ctx.apiMessages.map { ["role": $0.role, "content": $0.content] }, options: [.prettyPrinted])).flatMap { String(data: $0, encoding: .utf8) } ?? "无"  // 补充 C：调试信息（不持久化）
        lastDebugInfo = DebugInfo(
            promptJSON: promptJSON,
            apiResponse: ctx.fullResponse.isEmpty ? "无" : ctx.fullResponse,
            embeddingDimension: ctx.queryEmbedding.count,
            toolCalls: currentToolSteps.map { DebugInfo.ToolCallDebug(toolName: $0.toolName, arguments: $0.arguments, result: $0.result ?? "") },
            provider: lastUsedProvider?.displayName,
            fallbackUsed: didFallbackLastRequest
        )

        endLiveActivity()
    }

    // MARK: - Day 12: 反馈闭环（转发至 FeedbackCoordinator）

    /// 提交用户对 assistant 消息的反馈，触发 RAG chunk 权重调整。
    func submitFeedback(messageId: UUID, isPositive: Bool, citations: [DocumentChunk], modelContext: ModelContext) {
        feedbackCoordinator.submitFeedback(messageId: messageId, isPositive: isPositive, citations: citations, modelContext: modelContext)
    }

    /// 便捷方法：处理用户反馈点击，更新 UI 状态并持久化（feedbackStates / feedbackToast 由 coordinator 闭包回调驱动）。
    func handleFeedback(messageId: UUID, isPositive: Bool, modelContext: ModelContext) {
        feedbackCoordinator.handleFeedback(messageId: messageId, isPositive: isPositive, modelContext: modelContext)
    }

    // MARK: - 补充 D：Live Activities 灵动岛（转发至 LiveActivityCoordinator，iOS 16.1+ 可用，低版本静默降级）
    private func startLiveActivity(query: String) {
        #if os(iOS)
        liveActivityCoordinator.start(query: query)
        #endif
    }
    private func updateLiveActivity(status: String) {
        #if os(iOS)
        liveActivityCoordinator.update(status: status)
        #endif
    }
    private func endLiveActivity() {
        #if os(iOS)
        liveActivityCoordinator.end()
        #endif
    }

    // MARK: - PromptBuilder 转发（P2-6 Task 8，测试性调整为 internal 便于单测，行为零回归）
    func limitTokens(_ messages: [APIMessage], max: Int) -> [APIMessage] { promptBuilder.limitTokens(messages, max: max) }
    func buildEffectiveSystemPrompt(base: String, preference: UserPreference) -> String { promptBuilder.buildEffectiveSystemPrompt(base: base, preference: preference) }
}
