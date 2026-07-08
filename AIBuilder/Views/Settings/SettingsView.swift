import SwiftUI
import SwiftData
#if os(iOS)
import MessageUI
#endif

// MARK: - SettingsSection

/// 设置页分类,用于 iPad/macOS NavigationSplitView 左侧导航
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case provider
    case inference
    case voice
    case features
    case health
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: return "API 与模型"
        case .inference: return "推理配置"
        case .voice: return "语音朗读"
        case .features: return "功能与偏好"
        case .health: return "健康"
        case .about: return "关于"
        }
    }

    var icon: String {
        switch self {
        case .provider: return "network"
        case .inference: return "cpu"
        case .voice: return "speaker.wave.2"
        case .features: return "switch.2"
        case .health: return "heart.text.square"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var settingsVM: SettingsViewModel
    @Bindable var chatViewModel: ChatViewModel
    let conversation: Conversation?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // Day 20: 打开 mailto: URL
    @Environment(\.openURL) private var openURL
    // iPad/macOS 双栏:size class 判断
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Day 9: 用户偏好本地状态
    @State private var preferredTone: String = "默认"
    @State private var preferredTools: Set<String> = []
    @State private var customFact: String = ""
    // Day 9: 调试面板 sheet 开关
    @State private var showDebugPanel: Bool = false
    @State private var showDeleteAPIKeyConfirm = false
    // Day 17: 健康管理状态(iOS only —— macOS 下不渲染健康入口)
    #if os(iOS)
    @State private var healthAuthorizationStatus: String = "未授权"
    @State private var healthInsightCount: Int = 0
    #endif
    // Day 20: 邮件 composer sheet 开关
    @State private var showMailComposer: Bool = false
    // TTS 试听服务（独立于 ChatViewModel.voiceService，避免污染主朗读状态）
    @State private var ttsPreviewService = VoiceService()
    // iPad/macOS 双栏:当前选中的设置分类
    @State private var selectedSection: SettingsSection? = .provider

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .onAppear { handleAppear() }
        .onDisappear { handleDisappear() }
        .sheet(isPresented: $showDebugPanel) {
            DebugPanelView(chatViewModel: chatViewModel)
        }
        // Day 20: 邮件 composer sheet
        #if os(iOS)
        .sheet(isPresented: $showMailComposer) {
            MailComposerView { _ in
                // 用户完成或取消邮件后无需特殊处理（MFMailComposeResult 类型）
            }
        }
        #endif
    }

    // MARK: - Compact (iPhone)

    @ViewBuilder
    private var compactLayout: some View {
        NavigationStack {
            Form {
                providerSection
                fallbackSection
                bffSection
                onDeviceSection
                #if os(iOS)
                healthSection
                #endif
                voiceSection
                apiConfigSection
                modelSection
                featuresSection
                systemPromptSection
                if let msg = settingsVM.saveMessage {
                    saveMessageSection(msg)
                }
                preferenceSection
                debugSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    doneButton
                }
            }
            #endif
        }
    }

    // MARK: - Regular (iPad / macOS)

    @ViewBuilder
    private var regularLayout: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(availableSections) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    doneButton
                }
            }
        } detail: {
            NavigationStack {
                if let section = selectedSection {
                    Form {
                        sectionContent(for: section)
                    }
                    .formStyle(.grouped)
                    .navigationTitle(section.title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                } else {
                    ContentUnavailableView("选择一个分类", systemImage: "sidebar.left")
                }
            }
        }
    }

    /// macOS 下过滤掉健康分类(HealthKit 不可用)
    private var availableSections: [SettingsSection] {
        #if os(iOS)
        return SettingsSection.allCases
        #else
        return SettingsSection.allCases.filter { $0 != .health }
        #endif
    }

    @ViewBuilder
    private func sectionContent(for section: SettingsSection) -> some View {
        switch section {
        case .provider:
            providerSection
            fallbackSection
            apiConfigSection
            modelSection
        case .inference:
            bffSection
            onDeviceSection
        case .voice:
            voiceSection
        case .features:
            featuresSection
            systemPromptSection
            preferenceSection
        case .health:
            #if os(iOS)
            healthSection
            #else
            EmptyView()
            #endif
        case .about:
            if let msg = settingsVM.saveMessage {
                saveMessageSection(msg)
            }
            debugSection
            aboutSection
        }
    }

    // MARK: - 完成按钮

    private var doneButton: some View {
        Button("完成") {
            settingsVM.updateSystemPrompt(in: conversation, modelContext: modelContext)
            dismiss()
        }
        .fontWeight(.medium)
    }

    // MARK: - Section: 供应商

    @ViewBuilder
    private var providerSection: some View {
        // Day 13: 供应商选择
        Section {
            Picker("供应商", selection: $settingsVM.selectedProvider) {
                ForEach(ModelProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("选择 LLM 供应商")
        } header: {
            Text("供应商")
        } footer: {
            Text("选择 LLM 供应商。不同供应商的 API Key 独立存储。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 自动降级

    @ViewBuilder
    private var fallbackSection: some View {
        // Day 13: 自动降级开关
        Section {
            Toggle("启用自动降级", isOn: $settingsVM.enableFallback)
                .accessibilityHint("主供应商失败时自动切换备用供应商")
        } header: {
            Text("自动降级")
        } footer: {
            Text("主供应商失败时自动切换到备用供应商重试一次。")
                .font(.caption2)
        }
    }

    // MARK: - Section: BFF 代理

    @ViewBuilder
    private var bffSection: some View {
        // Day 15: BFF 代理配置
        Section {
            Toggle("启用 BFF 代理", isOn: $settingsVM.bffConfig.enabled)
            TextField("BFF endpoint", text: Binding(
                get: { settingsVM.bffConfig.endpointURL.absoluteString },
                set: { newValue in
                    // 输入合法 URL 时回写，非法输入保持原值
                    if let url = URL(string: newValue) {
                        settingsVM.bffConfig.endpointURL = url
                    }
                }
            ))
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            SecureField("BFF Token", text: $settingsVM.bffConfig.userToken)
                .textContentType(.password)
            Stepper("chat 限流（每分钟）：\(settingsVM.bffConfig.chatRateLimitPerMin)",
                    value: $settingsVM.bffConfig.chatRateLimitPerMin,
                    in: 5...60)
            Stepper("embed 限流（每分钟）：\(settingsVM.bffConfig.embedRateLimitPerMin)",
                    value: $settingsVM.bffConfig.embedRateLimitPerMin,
                    in: 5...30)
        } header: {
            Text("BFF 代理")
        } footer: {
            Text("启用后 API Key 由服务端保护，设备只持有 BFF Token。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 端侧推理

    @ViewBuilder
    private var onDeviceSection: some View {
        // Day 16: 端侧推理配置
        Section {
            Toggle("启用端侧推理", isOn: $settingsVM.onDeviceConfig.enabled)
                .accessibilityHint("启用后在断网时使用本地模型推理")
            NavigationLink("管理端侧模型") {
                OnDeviceModelView(settingsVM: settingsVM)
            }
            Toggle("断网自动切换", isOn: $settingsVM.onDeviceConfig.autoSwitchOnNetworkLoss)
                .accessibilityHint("断网时自动切换到端侧推理，联网后切回")
            Stepper("maxTokens：\(settingsVM.onDeviceConfig.maxTokens)",
                    value: $settingsVM.onDeviceConfig.maxTokens,
                    in: 128...2048)
            VStack(alignment: .leading) {
                Text("temperature：\(settingsVM.onDeviceConfig.temperature, specifier: "%.1f")")
                Slider(value: $settingsVM.onDeviceConfig.temperature, in: 0.0...1.0)
            }
        } header: {
            Text("端侧推理")
        } footer: {
            Text("端侧推理在断网时自动启用，模型文件约 700MB。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 健康 (iOS only)

    #if os(iOS)
    @ViewBuilder
    private var healthSection: some View {
        // Day 17: 健康管理
        Section {
            NavigationLink {
                HealthSettingsView(chatViewModel: chatViewModel)
            } label: {
                HStack {
                    Text("健康管理")
                    Spacer()
                    Text(healthAuthorizationStatus)
                        .foregroundStyle(healthAuthorizationStatus == "已授权" ? .green : .secondary)
                        .font(.caption)
                }
            }
            HStack {
                Text("已生成洞察")
                Spacer()
                Text("\(healthInsightCount)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("健康")
        } footer: {
            Text("接入 HealthKit 后 AI 可基于健康数据给出针对性建议。")
                .font(.caption2)
        }
    }
    #endif

    // MARK: - Section: 语音朗读

    @ViewBuilder
    private var voiceSection: some View {
        // MARK: 语音朗读
        Section {
            NavigationLink {
                TTSVoicePickerView(settingsVM: settingsVM, chatViewModel: chatViewModel)
            } label: {
                HStack {
                    Text("音色")
                    Spacer()
                    Text(currentVoiceDisplayName)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .accessibilityHint("选择系统内置 TTS 音色")

            VStack(alignment: .leading) {
                Text("语速：\(Int(settingsVM.ttsConfig.rate * 100))%")
                Slider(value: $settingsVM.ttsConfig.rate, in: 0...1, step: 0.05) { _ in
                    syncTTSConfigToChatViewModel()
                }
                .accessibilityValue("\(Int(settingsVM.ttsConfig.rate * 100))%")
            }
            .accessibilityLabel("语速")

            VStack(alignment: .leading) {
                Text("音调：\(settingsVM.ttsConfig.pitchMultiplier, specifier: "%.1f")")
                Slider(value: $settingsVM.ttsConfig.pitchMultiplier, in: 0.5...2.0, step: 0.1) { _ in
                    syncTTSConfigToChatViewModel()
                }
                .accessibilityValue("\(settingsVM.ttsConfig.pitchMultiplier, specifier: "%.1f")")
            }
            .accessibilityLabel("音调")

            VStack(alignment: .leading) {
                Text("音量：\(Int(settingsVM.ttsConfig.volume * 100))%")
                Slider(value: $settingsVM.ttsConfig.volume, in: 0...1, step: 0.05) { _ in
                    syncTTSConfigToChatViewModel()
                }
                .accessibilityValue("\(Int(settingsVM.ttsConfig.volume * 100))%")
            }
            .accessibilityLabel("音量")

            Button {
                if ttsPreviewService.isPreviewing {
                    ttsPreviewService.stopPreview()
                } else {
                    ttsPreviewService.previewVoice(
                        "你好,我是 AI Builder,很高兴为你服务。",
                        config: settingsVM.ttsConfig
                    )
                }
            } label: {
                Label(
                    ttsPreviewService.isPreviewing ? "停止试听" : "试听示例",
                    systemImage: ttsPreviewService.isPreviewing ? "stop.fill" : "play.fill"
                )
            }
            .accessibilityHint(ttsPreviewService.isPreviewing ? "停止试听" : "用当前音色朗读示例句")
        } header: {
            Text("语音朗读")
        } footer: {
            Text("选择朗读音色、语速、音调与音量。增强/优质音色首次使用时系统会自动下载。")
                .font(.caption2)
        }
    }

    // MARK: - Section: API 配置

    @ViewBuilder
    private var apiConfigSection: some View {
        // Day 13: API 配置按 selectedProvider 切换
        Section {
            Group {
                switch settingsVM.selectedProvider {
                case .deepseek:
                    SecureField("DeepSeek API Key", text: $settingsVM.deepseekAPIKey)
                        .textContentType(.password)
                    Button("保存 API Key") { settingsVM.saveAPIKey(for: .deepseek) }
                    Button("删除 API Key", role: .destructive) {
                        showDeleteAPIKeyConfirm = true
                    }
                case .qwen:
                    SecureField("Qwen API Key", text: $settingsVM.qwenAPIKey)
                        .textContentType(.password)
                    Button("保存 API Key") { settingsVM.saveAPIKey(for: .qwen) }
                    Button("删除 API Key", role: .destructive) {
                        showDeleteAPIKeyConfirm = true
                    }
                case .onDevice:
                    // 端侧推理无需 API Key，提示用户
                    Text("端侧推理无需 API Key，模型在本地运行。")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            .alert("删除 API Key", isPresented: $showDeleteAPIKeyConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    settingsVM.deleteAPIKey(for: settingsVM.selectedProvider)
                }
            } message: {
                Text("确定删除 \(settingsVM.selectedProvider.displayName) 的 API Key？删除后无法恢复。")
            }
        } header: {
            Text("API 配置")
        } footer: {
            Text("API Key 存储在系统 Keychain,不会离开本设备。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 模型

    @ViewBuilder
    private var modelSection: some View {
        Section {
            Picker("模型", selection: $settingsVM.modelSelectionMode) {
                Text("自动").tag("auto")
                Text("Chat").tag("deepseek-chat")
                Text("Reasoner").tag("deepseek-reasoner")
            }
            .pickerStyle(.segmented)
            .accessibilityHint("选自动时智能路由，选具体模型则固定使用")
        } header: {
            Text("模型")
        } footer: {
            Text("选「自动」时由智能路由根据消息特征决定；选具体模型时禁用智能路由。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 功能开关

    @ViewBuilder
    private var featuresSection: some View {
        Section {
            Toggle("启用 RAG 知识库", isOn: $chatViewModel.ragEnabled)
                .accessibilityHint("发送消息前检索本地知识库增强上下文")
            Toggle("启用工具调用", isOn: $chatViewModel.toolsEnabled)
                .accessibilityHint("启用后进入 ReAct 循环调用工具")
        } header: {
            Text("功能开关")
        } footer: {
            Text("RAG 启用后会在发送消息前检索本地知识库；工具调用启用后会进入 ReAct 循环。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 系统提示词

    @ViewBuilder
    private var systemPromptSection: some View {
        Section {
            HStack {
                Text("预设角色")
                    .font(.subheadline)
                Spacer()
                Menu("选择角色") {
                    ForEach(PresetPrompts.all, id: \.role) { preset in
                        Button(preset.role) {
                            settingsVM.systemPrompt = preset.prompt
                        }
                    }
                }
            }
            TextEditor(text: $settingsVM.systemPrompt)
                .frame(minHeight: 120)
                .accessibilityLabel("系统提示词")
        } header: {
            Text("系统提示词")
        } footer: {
            Text("当前会话生效。新建对话沿用此值。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 保存消息

    @ViewBuilder
    private func saveMessageSection(_ msg: String) -> some View {
        Section {
            Text(msg)
                .foregroundStyle(.green)
                .font(.footnote)
        }
    }

    // MARK: - Section: 用户偏好

    @ViewBuilder
    private var preferenceSection: some View {
        // MARK: Day 9 - 用户偏好
        Section {
            Picker("语气", selection: $preferredTone) {
                Text("默认").tag("默认")
                Text("正式").tag("正式")
                Text("轻松").tag("轻松")
            }

            // 偏好工具多选：从 ToolRegistry 取所有工具名，Toggle 多选
            ForEach(ToolRegistry.shared.allToolDefs, id: \.function.name) { toolDef in
                let name = toolDef.function.name
                Toggle(toolDef.function.description, isOn: Binding(
                    get: { preferredTools.contains(name) },
                    set: { isOn in
                        if isOn {
                            preferredTools.insert(name)
                        } else {
                            preferredTools.remove(name)
                        }
                    }
                ))
            }

            // 自定义事实多行输入，placeholder 用 overlay 实现
            TextEditor(text: $customFact)
                .frame(minHeight: 60)
                .overlay(alignment: .topLeading) {
                    if customFact.isEmpty {
                        Text("如：我是素食者…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("用户偏好")
        } footer: {
            Text("这些偏好会被注入到系统提示词，影响 AI 回复风格与工具选择。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 调试面板

    @ViewBuilder
    private var debugSection: some View {
        // MARK: Day 9 - 调试面板
        Section {
            Button("查看调试信息") {
                showDebugPanel = true
            }
        } header: {
            Text("调试面板")
        } footer: {
            Text("展示最近一次发送的 prompt、API 响应、embedding 维度与工具调用。")
                .font(.caption2)
        }
    }

    // MARK: - Section: 关于

    @ViewBuilder
    private var aboutSection: some View {
        // MARK: Day 20 - 关于
        Section {
            // 隐私政策
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                HStack {
                    Text("隐私政策")
                    Spacer()
                }
            }
            .accessibilityHint("查看 AI Builder 隐私政策")

            // 投诉反馈：优先使用系统邮件 composer，不可用时降级 mailto:
            Button {
                #if os(iOS)
                if MFMailComposeViewController.canSendMail() {
                    showMailComposer = true
                } else if let url = FeedbackService.shared.mailtoURL() {
                    openURL(url)
                }
                #else
                if let url = FeedbackService.shared.mailtoURL() {
                    openURL(url)
                }
                #endif
            } label: {
                HStack {
                    Text("投诉反馈")
                    Spacer()
                    Image(systemName: "envelope")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHint("通过邮件反馈问题或投诉")

            // App 版本号
            HStack {
                Text("版本")
                Spacer()
                Text(appVersionString)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Text("关于")
        } footer: {
            Text("AI Builder 致力于保护您的隐私")
                .font(.caption2)
        }
    }

    // MARK: - 生命周期

    private func handleAppear() {
        // Day 9: 从 SwiftData 加载用户偏好到本地状态
        let storage = ChatStorage(modelContext: modelContext)
        let pref = storage.fetchPreference()
        preferredTone = pref.preferredTone
        preferredTools = Set(pref.preferredTools)
        customFact = pref.customFact

        // Day 17: 刷新 HealthKit 授权状态与洞察数量
        refreshHealthStatus()

        Task {
            await settingsVM.loadAPIKeysFromKeychain()
        }
    }

    private func handleDisappear() {
        // Day 9: 离开页面时持久化用户偏好
        let storage = ChatStorage(modelContext: modelContext)
        storage.savePreference(
            tone: preferredTone,
            tools: Array(preferredTools),
            fact: customFact
        )
        // Day 15: 离开页面时持久化 BFF 配置
        settingsVM.saveBFFConfig()
        // Day 16: 离开页面时持久化端侧推理配置
        settingsVM.saveOnDeviceConfig()
    }

    // MARK: - Day 20: 关于 Section 辅助

    /// App 版本号字符串（CFBundleShortVersionString (CFBundleVersion)）
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Day 17: 健康状态刷新

    /// 刷新 HealthKit 授权状态文案与已生成洞察数量
    private func refreshHealthStatus() {
        #if os(iOS)
        // 授权状态：从 ChatViewModel 的 HealthKitService 读取（未注入则视为未授权）
        if let service = chatViewModel.healthKitService {
            healthAuthorizationStatus = service.isAuthorized ? "已授权" : "未授权"
        } else {
            healthAuthorizationStatus = "未授权"
        }
        // 洞察数量：用 FetchDescriptor 查询 HealthInsight 总数
        let descriptor = FetchDescriptor<HealthInsight>()
        healthInsightCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        #endif
    }

    // MARK: - TTS 配置同步

    /// 当前选中音色的可读名称（空 identifier 显示"系统默认"）
    private var currentVoiceDisplayName: String {
        if settingsVM.ttsConfig.voiceIdentifier.isEmpty {
            return "系统默认"
        }
        return TTSVoiceCatalog.displayName(for: settingsVM.ttsConfig.voiceIdentifier)
    }

    /// 同步 SettingsViewModel 的 ttsConfig 到 ChatViewModel（朗读时使用最新配置）
    private func syncTTSConfigToChatViewModel() {
        chatViewModel.ttsConfig = settingsVM.ttsConfig
        settingsVM.updateTTSConfig(settingsVM.ttsConfig)
    }
}

// MARK: - Day 9: 调试面板
/// 展示最近一次发送的完整 prompt、API 原始响应、embedding 维度与工具调用列表
struct DebugPanelView: View {
    @Bindable var chatViewModel: ChatViewModel
    // Day 14: 远程配置 / 遥测状态（从 actor 异步读取展示）
    @State private var configVersion: Int = 0
    @State private var fetchedAt: Date?
    @State private var remoteDefaultProvider: String = ""
    @State private var maintenanceMode: Bool = false
    @State private var telemetryBufferCount: Int = 0
    @State private var lastUploadAt: Date?
    @State private var lastUploadStatus: String = "idle"
    // Day 19: 性能指标（从 PerformanceMonitor actor 异步读取）
    @State private var performanceMetrics: [String: Double] = [:]

    var body: some View {
        NavigationStack {
            Form {
                // Day 19: 性能指标
                Section("性能指标") {
                    if performanceMetrics.isEmpty {
                        Text("暂无性能数据")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(performanceMetrics.sorted(by: { $0.key < $1.key }), id: \.key) { name, elapsed in
                            HStack {
                                Text(name)
                                Spacer()
                                Text(String(format: "%.1f ms", elapsed))
                                    .foregroundStyle(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    Button("清除性能指标") {
                        Task {
                            await PerformanceMonitor.shared.clear()
                            performanceMetrics = await PerformanceMonitor.shared.getMetrics()
                        }
                    }
                }

                // Day 14: 远程配置 / 遥测
                Section("远程配置 / 遥测") {
                    HStack {
                        Text("配置版本")
                        Spacer()
                        Text("\(configVersion)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("拉取时间")
                        Spacer()
                        Text(fetchedAt?.formatted(.dateTime) ?? "未拉取").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("默认供应商")
                        Spacer()
                        Text(remoteDefaultProvider).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("维护模式")
                        Spacer()
                        Text(maintenanceMode ? "是" : "否")
                            .foregroundStyle(maintenanceMode ? .red : .secondary)
                    }
                    HStack {
                        Text("缓冲事件数")
                        Spacer()
                        Text("\(telemetryBufferCount)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("上次上报时间")
                        Spacer()
                        Text(lastUploadAt?.formatted(.dateTime) ?? "从未").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("上次上报状态")
                        Spacer()
                        Text(lastUploadStatus).foregroundStyle(.secondary)
                    }
                    Button("立即上报") {
                        Task {
                            await LogUploader.shared.uploadIfNeeded()
                            await refreshTelemetry()
                        }
                    }
                    Button("重新拉取配置") {
                        Task {
                            await RemoteConfigService.shared.fetch()
                            await refreshConfig()
                        }
                    }
                }

                // Day 13: 供应商 / 模型 / 降级信息
                Section("供应商与降级") {
                    HStack {
                        Text("当前供应商")
                        Spacer()
                        Text(chatViewModel.lastUsedProvider?.displayName ?? "未发送")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("选中模型")
                        Spacer()
                        Text(chatViewModel.selectedProvider.defaultChatModel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("触发降级")
                        Spacer()
                        Text(chatViewModel.didFallbackLastRequest ? "是" : "否")
                            .foregroundStyle(chatViewModel.didFallbackLastRequest ? .orange : .secondary)
                    }
                }

                // 最近一次发送的完整 prompt JSON
                Section("最近 Prompt JSON") {
                    ScrollView {
                        Text(chatViewModel.lastDebugInfo?.promptJSON ?? "无")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 200)
                }

                // 最近一次 DeepSeek API 原始响应
                Section("API 原始响应") {
                    ScrollView {
                        Text(chatViewModel.lastDebugInfo?.apiResponse ?? "无")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 200)
                }

                // 最近一次 embedding 向量维度
                Section("Embedding 维度") {
                    if let dim = chatViewModel.lastDebugInfo?.embeddingDimension {
                        Text("\(dim) 维")
                    } else {
                        Text("无")
                    }
                }

                // 最近一次工具调用参数与返回值
                Section("工具调用") {
                    if let calls = chatViewModel.lastDebugInfo?.toolCalls, !calls.isEmpty {
                        ForEach(calls) { call in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(call.toolName)
                                    .font(.headline)
                                Text("参数：\(call.arguments)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("返回：\(call.result)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("无工具调用")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("调试信息")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await refreshConfig()
                await refreshTelemetry()
                // Day 19: 拉取性能指标
                performanceMetrics = await PerformanceMonitor.shared.getMetrics()
            }
        }
    }

    // Day 14: 从 actor 异步读取远程配置到本地 @State
    private func refreshConfig() async {
        let config = await RemoteConfigService.shared.currentConfig
        configVersion = config.configVersion
        fetchedAt = config.fetchedAt
        remoteDefaultProvider = config.defaultProvider
        maintenanceMode = config.maintenanceMode
    }

    // Day 14: 从 actor 异步读取遥测状态到本地 @State
    private func refreshTelemetry() async {
        telemetryBufferCount = await TelemetryService.shared.bufferCount
        lastUploadAt = await LogUploader.shared.lastUploadAt
        lastUploadStatus = await LogUploader.shared.lastUploadStatus
    }
}

// MARK: - Day 9: 调试信息数据结构
/// 封装一次完整请求流程的调试信息，由 ChatViewModel 在发送消息时填充
struct DebugInfo {
    /// 最近一次发送的完整 prompt JSON
    let promptJSON: String
    /// 最近一次 DeepSeek API 原始响应
    let apiResponse: String
    /// 最近一次 embedding 向量维度（无 embedding 时为 0）
    let embeddingDimension: Int
    /// 最近一次工具调用列表
    let toolCalls: [ToolCallDebug]
    // Day 13: 新增 provider / fallbackUsed 字段
    let provider: String?
    let fallbackUsed: Bool

    struct ToolCallDebug: Identifiable {
        let id = UUID()
        let toolName: String
        let arguments: String
        let result: String
    }
}
