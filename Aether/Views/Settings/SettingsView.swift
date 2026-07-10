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
    // macOS 下 NavigationSplitView + NavigationStack + sheet 三层嵌套会截断 dismiss，
    // 改用 @Binding 直达 sheet 的 isPresented
    @Binding var isPresented: Bool
    // Day 20: 打开 mailto: URL
    @Environment(\.openURL) private var openURL
    // iPad/macOS 双栏:size class 判断
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // 语言切换管理器
    @StateObject private var languageManager = LanguageManager.shared
    // 语言切换后是否需要提示重启
    @State private var showRestartAlert = false

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
        .alert("语言", isPresented: $showRestartAlert) {
            Button("完成") {}
        } message: {
            Text("重启 App 以应用语言更改")
        }
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
                languageSection
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
            .tint(Color.aetherPurple)
            .foregroundStyle(Color.starlight)
            .scrollContentBackground(.hidden)
            .background(Color.deepSpace.ignoresSafeArea())
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
            .tint(Color.aetherPurple)
            .foregroundStyle(Color.starlight)
            .scrollContentBackground(.hidden)
            .background(Color.deepSpace.ignoresSafeArea())
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } detail: {
            NavigationStack {
                if let section = selectedSection {
                    Form {
                        sectionContent(for: section)
                    }
                    .formStyle(.grouped)
                    .tint(Color.aetherPurple)
                    .foregroundStyle(Color.starlight)
                    .scrollContentBackground(.hidden)
                    .background(Color.deepSpace.ignoresSafeArea())
                    .navigationTitle(section.title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                } else {
                    ContentUnavailableView("选择一个分类", systemImage: "sidebar.left")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    doneButton
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
            languageSection
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
            isPresented = false
        }
        .fontWeight(.medium)
        .accessibilityLabel("完成")
        .accessibilityHint("保存设置并关闭")
        .accessibilityIdentifier("settingsDoneButton")
    }

    // MARK: - Section: 语言切换

    @ViewBuilder
    private var languageSection: some View {
        Section {
            // Picker 选择语言，选中后立即写入 AppleLanguages
            Picker("语言", selection: Binding(
                get: { languageManager.current },
                set: { newValue in
                    languageManager.current = newValue
                    showRestartAlert = true
                }
            )) {
                ForEach(LanguageManager.AppLanguage.allCases) { language in
                    Label(language.displayName, systemImage: language.icon)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("语言")
            .accessibilityHint("选择 App 界面语言，切换后需重启 App 生效")
            .accessibilityIdentifier("languagePicker")
        } header: {
            Text("语言")
        } footer: {
            Text("切换语言后需重启 App 生效。选择「跟随系统」将使用设备系统语言。")
                .font(.captionAI)
        }
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
            .accessibilityLabel("供应商")
            .accessibilityHint("选择 LLM 供应商")
            .accessibilityIdentifier("providerPicker")
        } header: {
            Text("供应商")
        } footer: {
            Text("选择 LLM 供应商。不同供应商的 API Key 独立存储。")
                .font(.captionAI)
        }
    }

    // MARK: - Section: 自动降级

    @ViewBuilder
    private var fallbackSection: some View {
        // Day 13: 自动降级开关
        Section {
            Toggle("启用自动降级", isOn: $settingsVM.enableFallback)
                .accessibilityLabel("启用自动降级")
                .accessibilityHint("主供应商失败时自动切换备用供应商")
                .accessibilityIdentifier("fallbackToggle")
        } header: {
            Text("自动降级")
        } footer: {
            Text("主供应商失败时自动切换到备用供应商重试一次。")
                .font(.captionAI)
        }
    }

    // MARK: - Section: BFF 代理

    @ViewBuilder
    private var bffSection: some View {
        // Day 15: BFF 代理配置
        Section {
            Toggle("启用 BFF 代理", isOn: $settingsVM.bffConfig.enabled)
                .accessibilityLabel("启用 BFF 代理")
                .accessibilityHint("启用后端代理转发 API 请求")
                .accessibilityIdentifier("bffToggle")
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
            .accessibilityLabel("BFF endpoint")
            .accessibilityHint("输入 BFF 服务地址")
            .accessibilityIdentifier("bffEndpointTextField")
            SecureField("BFF Token", text: $settingsVM.bffConfig.userToken)
                .textContentType(.password)
                .accessibilityLabel("BFF Token")
                .accessibilityHint("输入 BFF 访问令牌")
                .accessibilityIdentifier("bffTokenSecureField")
            Stepper(String(format: NSLocalizedString("chat 限流（每分钟）：%d", comment: ""), settingsVM.bffConfig.chatRateLimitPerMin),
                    value: $settingsVM.bffConfig.chatRateLimitPerMin,
                    in: 5...60)
                .accessibilityLabel("chat 限流")
                .accessibilityHint("设置 chat 接口每分钟最大请求数")
                .accessibilityIdentifier("bffChatRateLimitStepper")
            Stepper(String(format: NSLocalizedString("embed 限流（每分钟）：%d", comment: ""), settingsVM.bffConfig.embedRateLimitPerMin),
                    value: $settingsVM.bffConfig.embedRateLimitPerMin,
                    in: 5...30)
                .accessibilityLabel("embed 限流")
                .accessibilityHint("设置 embed 接口每分钟最大请求数")
                .accessibilityIdentifier("bffEmbedRateLimitStepper")
        } header: {
            Text("BFF 代理")
        } footer: {
            Text("启用后 API Key 由服务端保护，设备只持有 BFF Token。")
                .font(.captionAI)
        }
    }

    // MARK: - Section: 端侧推理

    @ViewBuilder
    private var onDeviceSection: some View {
        // Day 16: 端侧推理配置
        Section {
            Toggle("启用端侧推理", isOn: $settingsVM.onDeviceConfig.enabled)
                .accessibilityLabel("启用端侧推理")
                .accessibilityHint("启用后在断网时使用本地模型推理")
                .accessibilityIdentifier("onDeviceToggle")
            NavigationLink("管理端侧模型") {
                OnDeviceModelView(settingsVM: settingsVM)
            }
            .accessibilityLabel("管理端侧模型")
            .accessibilityHint("下载或删除本地端侧模型")
            .accessibilityIdentifier("manageOnDeviceModelsLink")
            Toggle("断网自动切换", isOn: $settingsVM.onDeviceConfig.autoSwitchOnNetworkLoss)
                .accessibilityLabel("断网自动切换")
                .accessibilityHint("断网时自动切换到端侧推理，联网后切回")
                .accessibilityIdentifier("autoSwitchOnNetworkLossToggle")
            Stepper(String(format: NSLocalizedString("maxTokens：%d", comment: ""), settingsVM.onDeviceConfig.maxTokens),
                    value: $settingsVM.onDeviceConfig.maxTokens,
                    in: 128...2048)
                .accessibilityLabel("maxTokens")
                .accessibilityHint("设置端侧模型最大生成 token 数")
                .accessibilityIdentifier("onDeviceMaxTokensStepper")
            VStack(alignment: .leading) {
                Text(String(format: NSLocalizedString("temperature：%.1f", comment: ""), settingsVM.onDeviceConfig.temperature))
                Slider(value: $settingsVM.onDeviceConfig.temperature, in: 0.0...1.0)
                    .accessibilityLabel("temperature")
                    .accessibilityHint("调整模型生成随机程度")
                    .accessibilityIdentifier("onDeviceTemperatureSlider")
            }
        } header: {
            Text("端侧推理")
        } footer: {
            Text("端侧推理在断网时自动启用，模型文件约 700MB。")
                .font(.captionAI)
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
                        .font(.captionAI)
                }
            }
            .accessibilityLabel("健康管理")
            .accessibilityHint("管理 HealthKit 授权与健康洞察")
            .accessibilityIdentifier("healthManagementLink")
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
                .font(.captionAI)
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
                        .font(.captionAI)
                }
            }
            .accessibilityLabel("音色")
            .accessibilityHint("选择系统内置 TTS 音色")
            .accessibilityIdentifier("voicePickerLink")

            VStack(alignment: .leading) {
                Text(String(format: NSLocalizedString("语速：%d%%", comment: ""), Int(settingsVM.ttsConfig.rate * 100)))
                Slider(value: $settingsVM.ttsConfig.rate, in: 0...1, step: 0.05) { _ in
                    syncTTSConfigToChatViewModel()
                }
                .accessibilityValue(Text(String(format: NSLocalizedString("%d%%", comment: ""), Int(settingsVM.ttsConfig.rate * 100))))
                .accessibilityHint("调整朗读语速")
                .accessibilityIdentifier("ttsRateSlider")
            }
            .accessibilityLabel("语速")

            VStack(alignment: .leading) {
                Text(String(format: NSLocalizedString("音调：%.1f", comment: ""), settingsVM.ttsConfig.pitchMultiplier))
                Slider(value: $settingsVM.ttsConfig.pitchMultiplier, in: 0.5...2.0, step: 0.1) { _ in
                    syncTTSConfigToChatViewModel()
                }
                .accessibilityValue(Text(String(format: NSLocalizedString("%.1f", comment: ""), settingsVM.ttsConfig.pitchMultiplier)))
                .accessibilityHint("调整朗读音调")
                .accessibilityIdentifier("ttsPitchSlider")
            }
            .accessibilityLabel("音调")

            VStack(alignment: .leading) {
                Text(String(format: NSLocalizedString("音量：%d%%", comment: ""), Int(settingsVM.ttsConfig.volume * 100)))
                Slider(value: $settingsVM.ttsConfig.volume, in: 0...1, step: 0.05) { _ in
                    syncTTSConfigToChatViewModel()
                }
                .accessibilityValue(Text(String(format: NSLocalizedString("%d%%", comment: ""), Int(settingsVM.ttsConfig.volume * 100))))
                .accessibilityHint("调整朗读音量")
                .accessibilityIdentifier("ttsVolumeSlider")
            }
            .accessibilityLabel("音量")

            Button {
                if chatViewModel.voiceService.isPreviewing {
                    chatViewModel.voiceService.stopPreview()
                } else {
                    chatViewModel.voiceService.previewVoice(
                        "你好,我是以太,很高兴为你服务。",
                        config: settingsVM.ttsConfig
                    )
                }
            } label: {
                Label(
                    chatViewModel.voiceService.isPreviewing ? "停止试听" : "试听示例",
                    systemImage: chatViewModel.voiceService.isPreviewing ? "stop.fill" : "play.fill"
                )
            }
            .accessibilityLabel(chatViewModel.voiceService.isPreviewing ? "停止试听" : "试听示例")
            .accessibilityHint(chatViewModel.voiceService.isPreviewing ? "停止试听" : "用当前音色朗读示例句")
            .accessibilityIdentifier("previewVoiceButton")
        } header: {
            Text("语音朗读")
        } footer: {
            Text("选择朗读音色、语速、音调与音量。增强/优质音色首次使用时系统会自动下载。")
                .font(.captionAI)
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
                        .accessibilityLabel("DeepSeek API Key")
                        .accessibilityHint("输入 DeepSeek API 密钥")
                        .accessibilityIdentifier("deepseekAPIKeySecureField")
                    Button("保存 API Key") { settingsVM.saveAPIKey(for: .deepseek) }
                        .accessibilityLabel("保存 API Key")
                        .accessibilityHint("保存当前供应商的 API Key 到系统钥匙串")
                        .accessibilityIdentifier("saveAPIKeyButton")
                    Button("删除 API Key", role: .destructive) {
                        showDeleteAPIKeyConfirm = true
                    }
                    .accessibilityLabel("删除 API Key")
                    .accessibilityHint("删除当前供应商已保存的 API Key")
                    .accessibilityIdentifier("deleteAPIKeyButton")
                case .qwen:
                    SecureField("Qwen API Key", text: $settingsVM.qwenAPIKey)
                        .textContentType(.password)
                        .accessibilityLabel("Qwen API Key")
                        .accessibilityHint("输入 Qwen API 密钥")
                        .accessibilityIdentifier("qwenAPIKeySecureField")
                    Button("保存 API Key") { settingsVM.saveAPIKey(for: .qwen) }
                        .accessibilityLabel("保存 API Key")
                        .accessibilityHint("保存当前供应商的 API Key 到系统钥匙串")
                        .accessibilityIdentifier("saveAPIKeyButton")
                    Button("删除 API Key", role: .destructive) {
                        showDeleteAPIKeyConfirm = true
                    }
                    .accessibilityLabel("删除 API Key")
                    .accessibilityHint("删除当前供应商已保存的 API Key")
                    .accessibilityIdentifier("deleteAPIKeyButton")
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
                Text(String(format: NSLocalizedString("确定删除 %@ 的 API Key？删除后无法恢复。", comment: ""), settingsVM.selectedProvider.displayName))
            }
        } header: {
            Text("API 配置")
        } footer: {
            Text("API Key 存储在系统 Keychain,不会离开本设备。")
                .font(.captionAI)
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
            .accessibilityLabel("模型")
            .accessibilityHint("选自动时智能路由，选具体模型则固定使用")
            .accessibilityIdentifier("modelPicker")
        } header: {
            Text("模型")
        } footer: {
            Text("选「自动」时由智能路由根据消息特征决定；选具体模型时禁用智能路由。")
                .font(.captionAI)
        }
    }

    // MARK: - Section: 功能开关

    @ViewBuilder
    private var featuresSection: some View {
        Section {
            Toggle("启用 RAG 知识库", isOn: $chatViewModel.ragEnabled)
                .accessibilityLabel("启用 RAG 知识库")
                .accessibilityHint("发送消息前检索本地知识库增强上下文")
                .accessibilityIdentifier("ragToggle")
            Toggle("启用工具调用", isOn: $chatViewModel.toolsEnabled)
                .accessibilityLabel("启用工具调用")
                .accessibilityHint("启用后进入 ReAct 循环调用工具")
                .accessibilityIdentifier("toolsToggle")
        } header: {
            Text("功能开关")
        } footer: {
            Text("RAG 启用后会在发送消息前检索本地知识库；工具调用启用后会进入 ReAct 循环。")
                .font(.captionAI)
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
                .accessibilityLabel("选择角色")
                .accessibilityHint("选择预设系统提示词角色")
                .accessibilityIdentifier("presetRoleMenu")
            }
            TextEditor(text: $settingsVM.systemPrompt)
                .frame(minHeight: 120)
                .accessibilityLabel("系统提示词")
                .accessibilityHint("输入系统提示词以定义 AI 行为")
                .accessibilityIdentifier("systemPromptTextEditor")
        } header: {
            Text("系统提示词")
        } footer: {
            Text("当前会话生效。新建对话沿用此值。")
                .font(.captionAI)
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
            .accessibilityLabel("语气")
            .accessibilityHint("选择 AI 回复的语气风格")
            .accessibilityIdentifier("tonePicker")

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
                .accessibilityLabel(toolDef.function.description)
                .accessibilityHint("启用或禁用此工具")
                .accessibilityIdentifier("toolToggle_\(name)")
            }

            // 自定义事实多行输入，placeholder 用 overlay 实现
            TextEditor(text: $customFact)
                .frame(minHeight: 60)
                .accessibilityLabel("自定义事实")
                .accessibilityHint("输入 AI 需要了解的个性化事实")
                .accessibilityIdentifier("customFactTextEditor")
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
                .font(.captionAI)
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
            .accessibilityLabel("查看调试信息")
            .accessibilityHint("打开调试信息面板")
            .accessibilityIdentifier("openDebugPanelButton")
        } header: {
            Text("调试面板")
        } footer: {
            Text("展示最近一次发送的 prompt、API 响应、embedding 维度与工具调用。")
                .font(.captionAI)
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
            .accessibilityLabel("隐私政策")
            .accessibilityHint("查看以太隐私政策")
            .accessibilityIdentifier("privacyPolicyLink")

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
            .accessibilityLabel("投诉反馈")
            .accessibilityHint("通过邮件反馈问题或投诉")
            .accessibilityIdentifier("feedbackButton")

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
            Text("以太致力于保护您的隐私")
                .font(.captionAI)
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
                    .accessibilityLabel("清除性能指标")
                    .accessibilityHint("清空本地记录的性能指标数据")
                    .accessibilityIdentifier("clearPerformanceMetricsButton")
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
                    .accessibilityLabel("立即上报")
                    .accessibilityHint("立即上传缓存的遥测日志")
                    .accessibilityIdentifier("uploadTelemetryButton")
                    Button("重新拉取配置") {
                        Task {
                            await RemoteConfigService.shared.fetch()
                            await refreshConfig()
                        }
                    }
                    .accessibilityLabel("重新拉取配置")
                    .accessibilityHint("从服务器获取最新远程配置")
                    .accessibilityIdentifier("refreshRemoteConfigButton")
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
                        Text(String(format: NSLocalizedString("%d 维", comment: ""), dim))
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
                                    .font(.headlineAI)
                                Text(String(format: NSLocalizedString("参数：%@", comment: ""), call.arguments))
                                    .font(.captionAI)
                                    .foregroundStyle(.secondary)
                                Text(String(format: NSLocalizedString("返回：%@", comment: ""), call.result))
                                    .font(.captionAI)
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
