import SwiftUI
import SwiftData

#if os(macOS)

/// Task 24: macOS 菜单栏常驻模式面板。
///
/// 从菜单栏图标展开的 popover，提供：
/// - 快捷输入框：输入问题后回车即创建新会话并发送消息
/// - 最近对话列表：展示最近 5 个会话，点击在主窗口打开
struct MenuBarPanel: View {
    /// 快捷输入文本
    @State private var inputText = ""
    /// 最近对话列表（最多 5 个）
    @State private var recentConversations: [Conversation] = []
    /// 独立的 ChatViewModel 实例——处理菜单栏发出的快捷消息
    @State private var viewModel = ChatViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // 快捷输入框
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.aetherPurple)
                    .font(.title3)
                TextField("快捷提问...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendQuickMessage()
                    }
                    .accessibilityLabel("快捷提问输入框")
                    .accessibilityHint("输入问题后按回车发送，将创建新会话")
                    .accessibilityIdentifier("menuBarQuickInputField")
            }
            .padding(Spacing.md)
            .background(Color.liquidGlass.opacity(0.3))

            Divider()

            // 最近对话列表
            if recentConversations.isEmpty {
                emptyState
            } else {
                List {
                    Section("最近对话") {
                        ForEach(recentConversations) { conv in
                            Button {
                                openConversation(conv)
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "bubble.left")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(conv.title)
                                        .font(.bodyAI)
                                        .foregroundStyle(Color.starlight)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(conv.createdAt, style: .relative)
                                        .font(.captionAI)
                                        .foregroundStyle(Color.duskGray)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("打开会话 \(conv.title)")
                            .accessibilityHint("在主窗口打开此会话")
                            .accessibilityIdentifier("menuBarConversationRow_\(conv.id.uuidString)")
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 320, height: 400)
        .background(Color.deepSpace.opacity(0.95))
        .onAppear { loadRecentConversations() }
    }

    /// 空状态视图——无最近对话时展示
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("暂无最近对话")
                .font(.captionAI)
                .foregroundStyle(.secondary)
            Text("在上方输入问题开始")
                .font(.captionAI)
                .foregroundStyle(Color.duskGray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("暂无最近对话")
        .accessibilityIdentifier("menuBarEmptyState")
    }

    // MARK: - 交互

    /// 发送快捷提问——创建新会话并触发消息处理。
    /// 处理在后台进行，用户可在主窗口查看完整对话。
    private func sendQuickMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let storage = ChatStorage(modelContext: modelContext)
        // 创建新会话
        let conversation = storage.createConversation(
            title: "快捷提问",
            systemPrompt: "你是一个有帮助的AI助手。"
        )
        // 切换 ViewModel 到新会话并发送消息
        viewModel.switchTo(conversation: conversation)
        viewModel.inputText = text
        viewModel.sendMessage(in: conversation, modelContext: modelContext)

        // 清空输入框并刷新最近对话列表
        inputText = ""
        loadRecentConversations()
    }

    /// 加载最近 5 个对话（按 ChatStorage.fetchConversations 排序——置顶优先，再按 order/createdAt）
    private func loadRecentConversations() {
        let storage = ChatStorage(modelContext: modelContext)
        recentConversations = Array(storage.fetchConversations().prefix(5))
    }

    /// 在主窗口打开指定会话——发送通知由 ChatView 监听后切换会话并激活主窗口
    private func openConversation(_ conversation: Conversation) {
        NotificationCenter.default.post(
            name: .openConversationFromMenuBar,
            object: nil,
            userInfo: ["conversationId": conversation.id.uuidString]
        )
        // 激活应用使主窗口获得焦点
        NSApp.activate(ignoringOtherApps: true)
    }
}

#endif
