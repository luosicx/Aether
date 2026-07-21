import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import os
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
#if os(iOS)
import MessageUI
#endif

// MARK: - SettingsView
//
// 注意：SettingsSection 枚举已拆分到 SettingsSection.swift；
// DebugPanelView 与 DebugInfo 已分别拆分到 DebugPanelView.swift 与 Models/DebugInfo.swift。

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
    // 语言切换管理器（单例对象，使用 @ObservedObject 而非 @StateObject）
    @ObservedObject private var languageManager = LanguageManager.shared
    // 语言切换后是否需要提示重启
    @State private var showRestartAlert = false

    // Day 9: 用户偏好本地状态
    @State private var preferredTone: String = "默认"
    @State private var preferredTools: Set<String> = []
    @State private var customFact: String = ""
    // Task 25: 主题选择
    @State private var selectedTheme: AetherTheme = .deepSpace
    // Task 26: AI 人设
    @State private var aiPersona: String = ""
    @State private var aiPersonaDescription: String = ""
    @State private var aiAvatarData: Data? = nil
    @State private var showAvatarImporter: Bool = false
    // Task: 修复头像选择器——iOS 上使用 PhotosPicker 替代 fileImporter
    @State private var avatarPhotoItem: PhotosPickerItem?
    // Task 27: 气泡样式
    @State private var selectedBubbleStyle: BubbleStyleType = .liquidGlass
    // Task 28: 字体大小与行距
    @State private var fontSize: Double = 16.0
    @State private var lineHeight: Double = 1.5
    // Day 9: 调试面板 sheet 开关
    @State private var showDebugPanel: Bool = false
    @State private var showDeleteAPIKeyConfirm = false
    // Day 17: 健康管理状态(iOS only —— macOS 下不渲染健康入口)
    #if os(iOS)
    @State private var healthAuthorizationStatus: String = String(localized: "未授权")
    @State private var healthInsightCount: Int = 0
    #endif
    // Day 20: 邮件 composer sheet 开关
    @State private var showMailComposer: Bool = false
    // iPad/macOS 双栏:当前选中的设置分类
    @State private var selectedSection: SettingsSection? = .provider
    // 危险工具授权 Alert 状态
    @State private var showToolAuthorizationAlert = false
    @State private var pendingToolName: String?
    // Task 14: iCloud 同步开关与状态（从 UserDefaults 读取，需重启 App 生效）
    @State private var iCloudSyncEnabled: Bool = false
    @State private var iCloudSyncStatusText: String = String(localized: "未启用")
    @State private var lastICloudSyncText: String = String(localized: "从未")
    @State private var showICloudRestartAlert: Bool = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .background {
            // 优化：Esc 键关闭设置 sheet
            Button("") { isPresented = false }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        }
        .onAppear { handleAppear() }
        .onDisappear { handleDisappear() }
        .alert("语言", isPresented: $showRestartAlert) {
            Button("完成") {}
        } message: {
            Text("重启 App 以应用语言更改", comment: "")
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
        // 危险工具启用风险提示
        .alert(NSLocalizedString("启用高危工具", comment: "危险工具授权弹窗标题"), isPresented: $showToolAuthorizationAlert) {
            Button(NSLocalizedString("取消", comment: "取消按钮"), role: .cancel) {
                pendingToolName = nil
            }
            Button(NSLocalizedString("确认启用", comment: "确认启用危险工具按钮"), role: .destructive) {
                if let name = pendingToolName {
                    settingsVM.authorizedToolsOnce.insert(name)
                    settingsVM.toggleTool(name: name)
                }
                pendingToolName = nil
            }
        } message: {
            Text(NSLocalizedString("该工具可执行系统命令或控制其他应用，存在安全风险。确定要启用吗？", comment: "危险工具授权风险提示"))
        }
        // Task 14: iCloud 同步开关切换后提示重启 App
        .alert(NSLocalizedString("需要重启 App", comment: "iCloud 同步切换重启提示标题"), isPresented: $showICloudRestartAlert) {
            Button(NSLocalizedString("好", comment: "确认按钮"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("iCloud 同步设置已更新，请重启 App 以应用新的存储配置。", comment: "iCloud 同步重启提示正文"))
        }
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
                dangerousToolsSection
                systemPromptSection
                if let msg = settingsVM.saveMessage {
                    saveMessageSection(msg)
                }
                preferenceSection
                themeSection
                aiPersonaSection
                avatarSection
                bubbleStyleSection
                fontSizeSection
                // Task 19 阶段 4: 记忆管理（导出/导入/清空/加密）
                MemorySettingsView()
                icloudSection
                debugSection
                aboutSection
            }
            .formStyle(.grouped)
            .responsiveLayout()
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
                    .frame(maxWidth: 600)
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
            dangerousToolsSection
            systemPromptSection
            preferenceSection
            themeSection
            aiPersonaSection
            avatarSection
            bubbleStyleSection
            fontSizeSection
            // Task 19 阶段 4: 记忆管理（导出/导入/清空/加密）
            MemorySettingsView()
        case .health:
            #if os(iOS)
            healthSection
            #else
            EmptyView()
            #endif
        case .icloud:
            icloudSection
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
            // Task: 修复 API Key 未自动保存——点击「完成」时也保存两个 provider 的 Key
            settingsVM.saveAPIKey(for: .deepseek)
            settingsVM.saveAPIKey(for: .qwen)
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
            Text("语言", comment: "")
        } footer: {
            Text("切换语言后需重启 App 生效。选择「跟随系统」将使用设备系统语言。", comment: "")
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
            Text("供应商", comment: "")
        } footer: {
            Text("选择 LLM 供应商。不同供应商的 API Key 独立存储。", comment: "")
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
            Text("自动降级", comment: "")
        } footer: {
            Text("主供应商失败时自动切换到备用供应商重试一次。", comment: "")
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
                get: { settingsVM.bffConfig.endpointURL?.absoluteString ?? "" },
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
            Text("BFF 代理", comment: "")
        } footer: {
            Text("启用后 API Key 由服务端保护，设备只持有 BFF Token。", comment: "")
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
            Text("端侧推理", comment: "")
        } footer: {
            Text("端侧推理在断网时自动启用，模型文件约 700MB。", comment: "")
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
                    Text("健康管理", comment: "")
                    Spacer()
                    Text(healthAuthorizationStatus)
                        .foregroundStyle(healthAuthorizationStatus == String(localized: "已授权") ? .green : .secondary)
                        .font(.captionAI)
                }
            }
            .accessibilityLabel("健康管理")
            .accessibilityHint("管理 HealthKit 授权与健康洞察")
            .accessibilityIdentifier("healthManagementLink")
            HStack {
                Text("已生成洞察", comment: "")
                Spacer()
                Text("\(healthInsightCount)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("健康", comment: "")
        } footer: {
            Text("接入 HealthKit 后 AI 可基于健康数据给出针对性建议。", comment: "")
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
                    Text("音色", comment: "")
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
            Text("语音朗读", comment: "")
        } footer: {
            Text("选择朗读音色、语速、音调与音量。增强/优质音色首次使用时系统会自动下载。", comment: "")
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
                    Text("端侧推理无需 API Key，模型在本地运行。", comment: "")
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
            Text("API 配置", comment: "")
        } footer: {
            Text("API Key 存储在系统 Keychain,不会离开本设备。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Section: 模型

    @ViewBuilder
    private var modelSection: some View {
        Section {
            Picker("模型", selection: $settingsVM.modelSelectionMode) {
                Text("自动", comment: "").tag("auto")
                Text("Chat").tag("deepseek-chat")
                Text("Reasoner").tag("deepseek-reasoner")
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("模型")
            .accessibilityHint("选自动时智能路由，选具体模型则固定使用")
            .accessibilityIdentifier("modelPicker")
        } header: {
            Text("模型", comment: "")
        } footer: {
            Text("选「自动」时由智能路由根据消息特征决定；选具体模型时禁用智能路由。", comment: "")
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
            // 插件管理入口
            NavigationLink {
                PluginSettingsView()
            } label: {
                HStack {
                    Text("插件管理", comment: "")
                    Spacer()
                    // Task 17：使用 AetherIcons.plugin 兜底渲染
                    AetherIcon.plugin.systemImage
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("插件管理")
            .accessibilityHint("管理已安装的插件，安装或卸载插件")
            .accessibilityIdentifier("pluginManagementLink")
            // MCP Server 配置入口
            NavigationLink {
                MCPSettingsView()
            } label: {
                HStack {
                    Text("MCP 配置", comment: "")
                    Spacer()
                }
            }
            .accessibilityLabel("MCP 配置")
            .accessibilityHint("管理 MCP Server 配置")
            .accessibilityIdentifier("mcpSettingsLink")
        } header: {
            Text("功能开关", comment: "")
        } footer: {
            Text("RAG 启用后会在发送消息前检索本地知识库；工具调用启用后会进入 ReAct 循环。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Section: 危险工具（macOS 高危工具开关）

    @ViewBuilder
    private var dangerousToolsSection: some View {
        let dangerousTools = ToolRegistry.shared.dangerousToolDefs
        if !dangerousTools.isEmpty {
            Section {
                ForEach(dangerousTools, id: \.name) { tool in
                    let name = tool.name
                    Toggle(displayNameForDangerousTool(name), isOn: Binding(
                        get: { settingsVM.enabledTools.contains(name) },
                        set: { isOn in
                            if isOn {
                                if ToolRegistry.shared.requiresAuthorization(name: name),
                                   !settingsVM.authorizedToolsOnce.contains(name) {
                                    pendingToolName = name
                                    showToolAuthorizationAlert = true
                                } else {
                                    settingsVM.toggleTool(name: name)
                                }
                            } else {
                                settingsVM.toggleTool(name: name)
                            }
                        }
                    ))
                    .accessibilityLabel(displayNameForDangerousTool(name))
                    .accessibilityHint("启用或禁用此高危工具")
                    .accessibilityIdentifier("dangerousToolToggle_\(name)")
                }
            } header: {
                Text(NSLocalizedString("危险工具", comment: "危险工具分组标题"))
            } footer: {
                Text(NSLocalizedString("以下工具可执行系统命令、控制其他应用或访问敏感信息，默认关闭。启用前请阅读风险提示。", comment: "危险工具分组底部说明"))
                    .font(.captionAI)
            }
        }
    }

    /// 将危险工具注册名映射为本地化的可读显示名称
    private func displayNameForDangerousTool(_ name: String) -> String {
        switch name {
        case "run_terminal_command":
            return NSLocalizedString("终端命令", comment: "终端命令工具显示名称")
        case "run_applescript":
            return NSLocalizedString("AppleScript", comment: "AppleScript 工具显示名称")
        case "control_safari":
            return NSLocalizedString("Safari 控制", comment: "Safari 控制工具显示名称")
        case "create_shortcut":
            return NSLocalizedString("快捷指令", comment: "快捷指令工具显示名称")
        default: return name
        }
    }

    // MARK: - Section: 系统提示词

    @ViewBuilder
    private var systemPromptSection: some View {
        Section {
            HStack {
                Text("预设角色", comment: "")
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
            Text("系统提示词", comment: "")
        } footer: {
            Text("当前会话生效。新建对话沿用此值。", comment: "")
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
                Text("默认", comment: "").tag("默认")
                Text("正式", comment: "").tag("正式")
                Text("轻松", comment: "").tag("轻松")
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
                        Text("如：我是素食者…", comment: "")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("用户偏好", comment: "")
        } footer: {
            Text("这些偏好会被注入到系统提示词，影响 AI 回复风格与工具选择。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Task 25: Section: 主题切换

    @ViewBuilder
    private var themeSection: some View {
        Section {
            Picker("主题", selection: Binding(
                get: { selectedTheme },
                set: { newValue in
                    selectedTheme = newValue
                    // 立即切换主题，获得实时预览效果；使用 themeTransition 统一过渡曲线
                    withAnimation(AnimationTokens.themeTransition) {
                        ThemeManager.shared.switchTheme(newValue)
                    }
                }
            )) {
                ForEach(AetherTheme.allCases) { theme in
                    Label(theme.displayName, systemImage: theme.iconName)
                        .tag(theme)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("主题")
            .accessibilityHint("选择 App 主题配色方案")
            .accessibilityIdentifier("themePicker")
        } header: {
            Text("主题", comment: "")
        } footer: {
            Text("切换主题将改变背景、气泡、文字配色。深空为默认深色主题，黎明为暖色浅色主题，极光为青绿深色主题。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Task 26: Section: AI 人设

    @ViewBuilder
    private var aiPersonaSection: some View {
        Section {
            TextField("AI 名称", text: $aiPersona)
                .accessibilityLabel("AI 名称")
                .accessibilityHint("设置 AI 助手的名称")
                .accessibilityIdentifier("aiPersonaNameField")
            TextEditor(text: $aiPersonaDescription)
                .frame(minHeight: 80)
                .accessibilityLabel("AI 性格描述")
                .accessibilityHint("描述 AI 助手的性格特征")
                .accessibilityIdentifier("aiPersonaDescriptionField")
                .overlay(alignment: .topLeading) {
                    if aiPersonaDescription.isEmpty {
                        Text("如：温和耐心、善于鼓励、回答简洁…", comment: "")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("AI 人设", comment: "")
        } footer: {
            Text("人设名称与性格描述会注入到系统提示词，影响 AI 的回复风格。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Task 26: Section: 头像选择

    @ViewBuilder
    private var avatarSection: some View {
        Section {
            // 预览当前头像
            HStack {
                AvatarView(role: .assistant, size: 48, avatarData: aiAvatarData)
                Spacer()
                if aiAvatarData != nil {
                    Button("清除头像", role: .destructive) {
                        aiAvatarData = nil
                    }
                    .accessibilityLabel("清除头像")
                    .accessibilityHint("移除当前自定义头像")
                    .accessibilityIdentifier("clearAvatarButton")
                }
            }
            // 预设头像选择
            HStack {
                ForEach(presetAvatarSymbols, id: \.self) { symbol in
                    Button {
                        aiAvatarData = renderSymbolToData(symbol)
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.electricBlue)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.electricBlue.opacity(0.15)))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("预设头像 \(symbol)")
                    .accessibilityIdentifier("presetAvatar_\(symbol)")
                }
            }
            // 自定义头像上传
            // Task: 修复头像选择器——iOS 用 PhotosPicker 打开相册，macOS 保留 fileImporter
            #if os(iOS)
            PhotosPicker(selection: $avatarPhotoItem, matching: .images) {
                Label("从相册选择头像", systemImage: "photo.badge.plus")
            }
            .accessibilityLabel("从相册选择头像")
            .accessibilityHint("上传自定义图片作为 AI 头像")
            .accessibilityIdentifier("uploadAvatarButton")
            #else
            Button {
                showAvatarImporter = true
            } label: {
                Label("从相册选择头像", systemImage: "photo.badge.plus")
            }
            .accessibilityLabel("从相册选择头像")
            .accessibilityHint("上传自定义图片作为 AI 头像")
            .accessibilityIdentifier("uploadAvatarButton")
            #endif
        } header: {
            Text("AI 头像", comment: "")
        } footer: {
            Text("选择预设头像或上传自定义图片。自定义头像将显示在对话气泡旁。", comment: "")
                .font(.captionAI)
        }
        #if os(iOS)
        .onChange(of: avatarPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    aiAvatarData = data
                }
            }
        }
        #else
        .fileImporter(
            isPresented: $showAvatarImporter,
            allowedContentTypes: [.image]
        ) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        aiAvatarData = data
                    }
                }
            case .failure:
                break
            }
        }
        #endif
    }

    /// 预设头像 SF Symbol 列表
    private var presetAvatarSymbols: [String] {
        ["sparkles", "person.fill", "robot", "face.smiling.fill", "wand.and.stars", "brain.head.fill"]
    }

    /// 将 SF Symbol 渲染为 PNG/TIFF Data，便于存储到 UserPreference.avatarData
    @MainActor
    private func renderSymbolToData(_ systemName: String) -> Data? {
        let view = ZStack {
            Circle().fill(Color.electricBlue.opacity(0.2))
            Image(systemName: systemName)
                .font(.system(size: 24))
                .foregroundStyle(Color.electricBlue)
        }
        .frame(width: 56, height: 56)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #if os(iOS)
        return renderer.uiImage?.pngData()
        #else
        return renderer.nsImage?.tiffRepresentation
        #endif
    }

    // MARK: - Task 27: Section: 气泡样式

    @ViewBuilder
    private var bubbleStyleSection: some View {
        Section {
            Picker("气泡样式", selection: $selectedBubbleStyle) {
                ForEach(BubbleStyleType.allCases) { style in
                    Label(style.displayName, systemImage: style.iconName)
                        .tag(style)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("气泡样式")
            .accessibilityHint("选择对话气泡的视觉风格")
            .accessibilityIdentifier("bubbleStylePicker")
        } header: {
            Text("气泡样式", comment: "")
        } footer: {
            Text("液态玻璃为默认毛玻璃效果，极简为无背景纯文本，卡片为带边框阴影样式。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Task 28: Section: 字体大小与行距

    @ViewBuilder
    private var fontSizeSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text(String(format: "字体大小：%.0f pt", fontSize))
                Slider(value: $fontSize, in: 12...24, step: 1.0)
                    .accessibilityLabel("字体大小")
                    .accessibilityHint("调整对话文字大小")
                    .accessibilityIdentifier("fontSizeSlider")
            }
            VStack(alignment: .leading) {
                Text(String(format: NSLocalizedString("行距：%.1f", comment: "行距滑杆当前值"), lineHeight))
                Slider(value: $lineHeight, in: 1.0...2.0, step: 0.1)
                    .accessibilityLabel("行距")
                    .accessibilityHint("调整对话文字行间距")
                    .accessibilityIdentifier("lineHeightSlider")
            }
            // 实时预览
            VStack(alignment: .leading, spacing: 4) {
                Text("预览", comment: "")
                    .font(.captionAI)
                    .foregroundStyle(.secondary)
                Text("你好，我是以太。这是字体大小与行距的预览效果。", comment: "")
                    .font(.system(size: fontSize))
                    .lineSpacing(CGFloat(fontSize) * CGFloat(lineHeight - 1))
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .background(Color.bubbleAI.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
        } header: {
            Text("字体与行距", comment: "")
        } footer: {
            Text("调整对话正文的字体大小和行距，设置后立即生效。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Section: iCloud 同步

    @ViewBuilder
    private var icloudSection: some View {
        // Task 14.4: iCloud 同步开关与状态显示
        // ModelContainer 在 App 启动时根据 UserDefaults `aether.icloud.enabled` 决定使用
        // CloudKit 还是本地存储；切换开关后必须重启 App 才能真正生效。
        Section {
            Toggle("启用 iCloud 同步", isOn: Binding(
                get: { iCloudSyncEnabled },
                set: { newValue in
                    iCloudSyncEnabled = newValue
                    AetherApp.setICloudSyncEnabled(newValue)
                    // 启用时记录一次时间戳作为占位「上次同步时间」
                    // SwiftData + CloudKit 未公开同步事件回调，此处仅作为 UI 显示数据源
                    if newValue {
                        AetherApp.lastICloudSyncDate = Date()
                    }
                    refreshICloudSyncStatus()
                    showICloudRestartAlert = true
                }
            ))
            .accessibilityLabel("启用 iCloud 同步")
            .accessibilityHint("开启后跨设备同步对话数据，需重启 App 生效")
            .accessibilityIdentifier("iCloudSyncToggle")

            HStack {
                Text("同步状态", comment: "")
                Spacer()
                Text(iCloudSyncStatusText)
                    .foregroundStyle(iCloudSyncEnabled ? .green : .secondary)
                    .font(.captionAI)
            }
            .accessibilityLabel("同步状态")
            .accessibilityHint("显示当前 iCloud 同步状态")
            .accessibilityIdentifier("iCloudSyncStatusRow")

            HStack {
                Text("上次同步时间", comment: "")
                Spacer()
                Text(lastICloudSyncText)
                    .foregroundStyle(.secondary)
                    .font(.captionAI)
            }
            .accessibilityLabel("上次同步时间")
            .accessibilityHint("显示上次 iCloud 同步的时间")
            .accessibilityIdentifier("iCloudLastSyncRow")

            HStack {
                Text("CloudKit 容器", comment: "")
                Spacer()
                Text(AetherApp.cloudKitContainerIdentifier)
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }
            .accessibilityLabel("CloudKit 容器")
            .accessibilityHint("显示当前使用的 CloudKit 容器标识")
            .accessibilityIdentifier("iCloudContainerRow")
        } header: {
            Text("iCloud 同步", comment: "")
        } footer: {
            Text("开启后对话将通过 iCloud CloudKit 在所有登录同一 Apple ID 的设备间同步。需要 Apple Developer 账号、登录 iCloud 且已声明 iCloud 容器。冲突采用 last writer wins 策略。切换开关后请重启 App 生效。", comment: "")
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
            Text("调试面板", comment: "")
        } footer: {
            Text("展示最近一次发送的 prompt、API 响应、embedding 维度与工具调用。", comment: "")
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
                    Text("隐私政策", comment: "")
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
                    Text("投诉反馈", comment: "")
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
                Text("版本", comment: "")
                Spacer()
                Text(appVersionString)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Text("关于", comment: "")
        } footer: {
            Text("以太致力于保护您的隐私", comment: "")
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
        // Task 25-28: 加载主题/人设/头像/气泡样式/字体设置
        selectedTheme = AetherTheme(rawValue: pref.themeName) ?? .deepSpace
        // 同步 UserPreference 的主题到 ThemeManager
        ThemeManager.shared.switchTheme(selectedTheme)
        aiPersona = pref.aiPersona
        aiPersonaDescription = pref.aiPersonaDescription
        aiAvatarData = pref.avatarData
        selectedBubbleStyle = BubbleStyleType(rawValue: pref.bubbleStyle) ?? .liquidGlass
        fontSize = pref.fontSize
        lineHeight = pref.lineHeight

        // Day 17: 刷新 HealthKit 授权状态与洞察数量
        refreshHealthStatus()

        // Task 14: 初始化 iCloud 同步状态（从 UserDefaults 读取）
        iCloudSyncEnabled = AetherApp.isICloudSyncEnabled
        refreshICloudSyncStatus()

        // 同步工具启用状态
        settingsVM.loadSettings()

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
        // Task 25-28: 持久化主题/人设/头像/气泡样式/字体设置到 UserPreference
        let pref = storage.fetchPreference()
        pref.themeName = selectedTheme.rawValue
        pref.aiPersona = aiPersona
        pref.aiPersonaDescription = aiPersonaDescription
        pref.avatarData = aiAvatarData
        pref.bubbleStyle = selectedBubbleStyle.rawValue
        pref.fontSize = fontSize
        pref.lineHeight = lineHeight
        // Task: 修复 API Key 未自动保存——离开页面时自动保存两个 provider 的 Key
        settingsVM.saveAPIKey(for: .deepseek)
        settingsVM.saveAPIKey(for: .qwen)
        // Day 15: 离开页面时持久化 BFF 配置
        settingsVM.saveBFFConfig()
        // Day 16: 离开页面时持久化端侧推理配置
        settingsVM.saveOnDeviceConfig()
        // Task: 修复字体与行距不持久化——显式保存所有 UserPreference 修改
        do {
            try modelContext.save()
        } catch {
            // 偏好持久化失败：用户离开设置页后下次进入会回退旧值
            Logger.storage.error("设置页 UserPreference 持久化失败 (下次进入回退旧值): \(error.localizedDescription, privacy: .public)")
        }
        // Task: 修复气泡样式不生效——通知聊天界面重新加载用户偏好
        NotificationCenter.default.post(name: .settingsDidUpdate, object: nil)
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
            healthAuthorizationStatus = service.isAuthorized ? String(localized: "已授权") : String(localized: "未授权")
        } else {
            healthAuthorizationStatus = String(localized: "未授权")
        }
        // 洞察数量：用 FetchDescriptor 查询 HealthInsight 总数
        let descriptor = FetchDescriptor<HealthInsight>()
        healthInsightCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        #endif
    }

    // MARK: - Task 14: iCloud 同步状态刷新

    /// 刷新 iCloud 同步状态文案与上次同步时间显示。
    /// SwiftData + CloudKit 未公开同步事件回调，此处仅根据 UserDefaults 开关状态
    /// 与占位的「上次同步时间」生成展示文案，不读取 CloudKit 实时同步状态。
    private func refreshICloudSyncStatus() {
        if iCloudSyncEnabled {
            iCloudSyncStatusText = String(localized: "已启用，等待同步")
        } else {
            iCloudSyncStatusText = String(localized: "未启用")
        }
        if let date = AetherApp.lastICloudSyncDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            lastICloudSyncText = formatter.string(from: date)
        } else {
            lastICloudSyncText = String(localized: "从未")
        }
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
