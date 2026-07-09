import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    // Day 19: iPad 适配——检测 size class，regular 用 NavigationSplitView 双栏
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel = ChatViewModel()
    @State private var conversationListVM = ConversationListVM()
    @State private var settingsVM = SettingsViewModel()
    @State private var currentConversation: Conversation?
    @State private var showConversationList = false
    @State private var showSettings = false
    @State private var showDocumentPicker = false
    @State private var showKnowledgeBase = false
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
                ConversationRow(conversation: conv)
                    .tag(conv)
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
            .navigationTitle(currentConversation?.title ?? "AI Builder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
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
                KnowledgeBaseView()
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
                    // 自动选中最近会话（若 currentConversation 为 nil 且存在已有会话）
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
                    onDismiss: { viewModel.errorMessage = nil }
                )
            }
            // Day 18: 接收 Handoff / NSUserActivity 搜索延续，切换到对应会话
            .onContinueUserActivity("com.aibuilder.conversation") { activity in
                guard let conversationIdString = activity.userInfo?["conversationId"] as? String,
                      let conversationId = UUID(uuidString: conversationIdString) else { return }
                switchToConversation(id: conversationId)
            }
            // Day 18: 接收 Spotlight deep link，解析 aibuilder://conversation/<uuid> 并切换会话
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
        }
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
    /// 支持格式：`aibuilder://conversation/<uuid>`
    private func handleDeepLink(_ url: URL) {
        // 校验 host 为 conversation，且 path 含合法 UUID
        guard url.host == "conversation" else { return }
        let uuidString = url.lastPathComponent
        guard let conversationId = UUID(uuidString: uuidString) else { return }
        switchToConversation(id: conversationId)
    }
}
