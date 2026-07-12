import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    // Day 19: iPad 适配——检测 size class，regular 用 NavigationSplitView 双栏
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(macOS)
    // Task 20: macOS 多窗口——openWindow 用于打开新窗口，conversationID 用于多窗口初始对话
    @Environment(\.openWindow) private var openWindow
    @Environment(\.conversationID) private var initialConversationID
    #endif
    @State private var viewModel = ChatViewModel()
    @State private var conversationListVM = ConversationListVM()
    @State private var settingsVM = SettingsViewModel()
    @State private var currentConversation: Conversation?
    @State private var showConversationList = false
    @State private var showSettings = false
    @State private var showDocumentPicker = false
    @State private var showKnowledgeBase = false
    // Task: macOS 分段工具栏切换的视图标签
    @State private var selectedTab: ViewTab = .chat
    // 统一 Toast：操作成功/复制/撤销反馈
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // Day 19: iPad regular——侧栏会话列表 + 主区对话
                NavigationSplitView {
                    conversationSidebar
                } detail: {
                    chatDetail
                }
            } else {
                // compact——保持现有 NavigationStack 单列布局
                chatDetail
            }
        }
        .toast(isPresented: $showToast, message: toastMessage)
    }

    /// Day 19: iPad 侧栏会话列表（regular 时内联展示，替代 sheet）
    private var conversationSidebar: some View {
        List(selection: Binding<Conversation?>(
            get: { currentConversation },
            set: { newValue in
                guard let conv = newValue else { return }
                conversationListVM.autoTitleIfNeeded(for: conv)
                currentConversation = conv
                settingsVM.loadSystemPrompt(from: conv)
                viewModel.switchTo(conversation: conv)
            }
        )) {
            ForEach(conversationListVM.conversations) { conv in
                #if os(macOS)
                // Task 20: macOS 支持拖拽会话到其他窗口
                DraggableConversation(conversation: conv)
                    .tag(conv)
                #else
                ConversationRow(conversation: conv)
                    .tag(conv)
                #endif
            }
        }
        .navigationTitle("对话")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailingCompat) {
                Button {
                    createNewConversation()
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.medium)
                }
                .accessibilityLabel("新建对话")
                .accessibilityHint("创建新对话")
                .accessibilityIdentifier("newConversationButton")
            }
        }
    }

    /// Day 19: 主区对话内容（compact 与 regular 共用）
    private var chatDetail: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(macOS)
                switch selectedTab {
                case .chat:
                    chatMainContent
                case .knowledge:
                    KnowledgeBaseView(provider: viewModel.selectedProvider)
                case .health:
                    HealthSettingsView(chatViewModel: viewModel)
                }
                #else
                chatMainContent
                #endif
            }
            .navigationTitle(currentConversation?.title ?? "以太")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                // Task: macOS 分段工具栏——切换 聊天 / 知识库 / 健康
                ToolbarItem(placement: .navigation) {
                    Picker("视图", selection: $selectedTab) {
                        Label("聊天", systemImage: "bubble.left").tag(ViewTab.chat)
                        Label("知识库", systemImage: "books.vertical").tag(ViewTab.knowledge)
                        Label("健康", systemImage: "heart.text.square").tag(ViewTab.health)
                    }
                    .pickerStyle(.segmented)
                }
                #endif
                // Day 19: compact 显示会话列表按钮；regular 时侧栏已可见，隐藏此按钮
                ToolbarItem(placement: .topBarLeadingCompat) {
                    if horizontalSizeClass != .regular {
                        Button { showConversationList = true } label: {
                            Image(systemName: "list.bullet")
                                .font(.titleAI)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("会话列表")
                        .accessibilityHint("打开会话列表")
                        .accessibilityIdentifier("conversationListButton")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailingCompat) {
                    Button {
                        showKnowledgeBase = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.titleAI)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("知识库")
                    .accessibilityHint("打开知识库管理")
                    .accessibilityIdentifier("knowledgeBaseToolbarButton")
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.titleAI)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("设置")
                    .accessibilityHint("打开设置")
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(isPresented: $showConversationList) {
                ConversationList(conversationListVM: conversationListVM, onSelect: { conv in
                    conversationListVM.autoTitleIfNeeded(for: conv)
                    currentConversation = conv
                    settingsVM.loadSystemPrompt(from: conv)
                    viewModel.switchTo(conversation: conv)
                    showConversationList = false
                }, onCreate: {
                    createNewConversation()
                })
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settingsVM: settingsVM, chatViewModel: viewModel, conversation: currentConversation, isPresented: $showSettings)
                    .onAppear {
                        settingsVM.loadSystemPrompt(from: currentConversation)
                    }
                    .onDisappear {
                        viewModel.selectedModel = settingsVM.selectedModel
                        // Day 13: 同步 provider
                        viewModel.selectedProvider = settingsVM.selectedProvider
                        viewModel.fallbackProvider = settingsVM.enableFallback ? settingsVM.selectedProvider.fallback : nil
                    }
            }
            .sheet(isPresented: $showKnowledgeBase) {
                KnowledgeBaseView(provider: viewModel.selectedProvider)
            }
            .onAppear {
                viewModel.selectedModel = settingsVM.selectedModel
                // Day 13: 同步 provider
                viewModel.selectedProvider = settingsVM.selectedProvider
                viewModel.fallbackProvider = settingsVM.enableFallback ? settingsVM.selectedProvider.fallback : nil
                // 只 load 会话列表，不创建新对话（避免触发 body 重算打断 TextField）
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 33_000_000)
                    conversationListVM.load(modelContext: modelContext)
                    // Task 20: macOS 多窗口——若通过 WindowGroup(for: UUID.self) 打开且指定了对话 ID，
                    // 则切换到该对话；否则自动选中最近会话
                    #if os(macOS)
                    if let targetID = initialConversationID {
                        switchToConversation(id: targetID)
                        return
                    }
                    #endif
                    if currentConversation == nil, let recent = conversationListVM.conversations.first {
                        currentConversation = recent
                        settingsVM.loadSystemPrompt(from: recent)
                        viewModel.switchTo(conversation: recent)
                    }
                }
            }
            .overlay(alignment: .top) {
                ErrorOverlay(
                    errorMessage: viewModel.errorMessage,
                    onDismiss: { viewModel.errorMessage = nil },
                    onRetry: nil,
                    onSettings: { showSettings = true }
                )
            }
            // Day 18: 接收 Handoff / NSUserActivity 搜索延续，切换到对应会话
            .onContinueUserActivity("com.aether.conversation") { activity in
                guard let conversationIdString = activity.userInfo?["conversationId"] as? String,
                      let conversationId = UUID(uuidString: conversationIdString) else { return }
                switchToConversation(id: conversationId)
            }
            // Day 18: 接收 Spotlight deep link，解析 aether://conversation/<uuid> 并切换会话
            .onOpenURL { url in
                handleDeepLink(url)
            }
            // Task 4: 监听 macOS 菜单栏命令通知 —— 新建对话 / 搜索会话 / 设置
            .onReceive(NotificationCenter.default.publisher(for: .newConversationRequested)) { _ in
                createNewConversation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchRequested)) { _ in
                showConversationList = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsRequested)) { _ in
                showSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearchRequested)) { _ in
                showConversationList = true
                // TODO: 后续可通过 FocusState 进一步聚焦到搜索框
            }
            #if os(macOS)
            // Task 20: macOS 监听「新建窗口」(Cmd+Shift+N) 通知——打开新窗口
            .onReceive(NotificationCenter.default.publisher(for: .newWindowRequested)) { _ in
                openWindow(value: UUID())
            }
            // Task 24: 菜单栏面板点击最近对话时——在主窗口打开指定会话
            .onReceive(NotificationCenter.default.publisher(for: .openConversationFromMenuBar)) { note in
                guard let idStr = note.userInfo?["conversationId"] as? String,
                      let conversationId = UUID(uuidString: idStr) else { return }
                // 重新加载会话列表以获取菜单栏创建的新会话
                conversationListVM.load(modelContext: modelContext, cleanupEmpty: false)
                // 在列表中查找目标会话
                if let conv = conversationListVM.conversations.first(where: { $0.id == conversationId }) {
                    conversationListVM.autoTitleIfNeeded(for: conv)
                    currentConversation = conv
                    settingsVM.loadSystemPrompt(from: conv)
                    viewModel.switchTo(conversation: conv)
                    showConversationList = false
                }
            }
            #endif
        }
    }

    /// 主聊天内容：消息列表 + 分隔线 + 输入栏。
    /// macOS 分段工具栏 `.chat` 分支与 iOS compact/regular 共用。
    private var chatMainContent: some View {
        VStack(spacing: 0) {
            MessageListView(viewModel: viewModel, conversation: currentConversation)
            Rectangle()
                .fill(Color.separator)
                .frame(height: 0.5)
            ChatInputBar(
                inputText: $viewModel.inputText,
                isLoading: viewModel.isLoading,
                isRecording: viewModel.isRecording,
                onSend: {
                    let conv: Conversation
                    if let existing = currentConversation {
                        conv = existing
                    } else {
                        // 首次发消息时创建新对话（不在启动时创建，避免阻塞）
                        guard let newConv = conversationListVM.createConversation(
                            title: "新对话",
                            systemPrompt: settingsVM.systemPrompt
                        ) else { return }
                        currentConversation = newConv
                        settingsVM.loadSystemPrompt(from: newConv)
                        conv = newConv
                    }
                    // Day 12: 同步模型选择模式到 ChatViewModel
                    viewModel.modelSelectionMode = settingsVM.modelSelectionMode
                    // Day 13: 同步 provider 配置
                    viewModel.selectedProvider = settingsVM.selectedProvider
                    viewModel.fallbackProvider = settingsVM.enableFallback ? settingsVM.selectedProvider.fallback : nil
                    viewModel.sendMessage(in: conv, modelContext: modelContext)
                },
                onPaperclip: {
                    showKnowledgeBase = true
                },
                onToggleVoice: {
                    viewModel.toggleVoiceInput()
                },
                onImagePicked: { data in
                    viewModel.pendingImage = data
                }
            )
        }
        // Task 19: 响应式布局——macOS 超宽屏限制最大宽度并居中
        .responsiveLayout()
    }

    /// Day 19: 创建新对话的公共逻辑（侧栏与 sheet 复用）
    private func createNewConversation() {
        if let conv = conversationListVM.createConversation(
            title: "新对话",
            systemPrompt: settingsVM.systemPrompt
        ) {
            currentConversation = conv
            settingsVM.loadSystemPrompt(from: conv)
            viewModel.switchTo(conversation: conv)
        }
    }

    /// Day 18: 通过 conversationId 切换到对应会话。
    /// 从 modelContext fetch 单条记录，未找到则忽略。
    private func switchToConversation(id: UUID) {
        var descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let conversation = try? modelContext.fetch(descriptor).first else { return }
        conversationListVM.autoTitleIfNeeded(for: conversation)
        currentConversation = conversation
        settingsVM.loadSystemPrompt(from: conversation)
        viewModel.switchTo(conversation: conversation)
    }

    /// Day 18: 解析 deep link URL 并切换到对应会话。
    /// 支持格式：`aether://conversation/<uuid>`
    private func handleDeepLink(_ url: URL) {
        // 校验 host 为 conversation，且 path 含合法 UUID
        guard url.host == "conversation" else { return }
        let uuidString = url.lastPathComponent
        guard let conversationId = UUID(uuidString: uuidString) else { return }
        switchToConversation(id: conversationId)
    }
}

/// Task: macOS 分段工具栏切换的视图标签
enum ViewTab: String, CaseIterable, Hashable {
    case chat, knowledge, health
}
