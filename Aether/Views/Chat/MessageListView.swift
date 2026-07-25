import SwiftUI
import AetherDesign
import AetherUI

/// Day 10: 独立的流式气泡视图，隔离 streamingText 渲染
/// 避免 chunk 更新触发 MessageListView 的 ForEach messages 全量重算
struct StreamingBubbleView: View {
    let text: String

    private var bubbleBackground: Color { Color.backgroundSecondary }
    private var bubbleShape: some Shape {
        #if os(iOS)
        return RoundedCornerShape(radius: 16, corners: [.topLeft, .topRight, .bottomRight])
        #else
        return UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 16, bottomLeading: 0, bottomTrailing: 16, topTrailing: 16)
        )
        #endif
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 0) {
                    Text(text)
                    Text("▍")
                        .foregroundStyle(.tertiary)
                        .modifier(BlinkingCursor())
                }
                .font(.bodyAI)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
            }
            Spacer(minLength: 48)
        }
    }
}

/// Task 12: 消息列表条目，同时携带快照（用于渲染）与原始 ChatMessage 引用（用于回调）
/// Hashable 仅基于 id；相等性基于 id + 快照内容，使 diffable data source 能检测内容变化并重载
private struct MessageListEntry: Identifiable, Hashable {
    let id: UUID
    let snapshot: MessageSnapshot
    let original: ChatMessage

    static func == (lhs: MessageListEntry, rhs: MessageListEntry) -> Bool {
        lhs.id == rhs.id && lhs.snapshot == rhs.snapshot
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Task 12: 自动滚动触发值——消息数 / 流式文本长度 / 加载状态变化时滚动到底部
private struct ScrollToken: Hashable {
    let messageCount: Int
    let streamingLength: Int
    let isLoading: Bool
}

/// Task 12: 内容刷新触发值——prefs / reduceMotion / feedbackStates / speakingMessageId 变化时
/// 强制重新配置所有消息 Cell，确保 iOS UICollectionView 中的 SwiftUI 内容同步更新
private struct ContentRefreshToken: Hashable {
    let bubbleStyle: String
    let fontSize: Double
    let lineHeight: Double
    let avatarDataHash: Int
    let reduceMotion: Bool
    let feedbackStatesHash: Int
    let speakingMessageId: UUID?
}

struct MessageListView: View {
    @Bindable var viewModel: ChatViewModel
    let conversation: Conversation?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Task 25-28: 用户偏好，在 onAppear 中加载，避免计算属性每次创建 ChatStorage 实例
    @State private var userPreference: UserPreference?

    var body: some View {
        // 安全解包用户偏好，未加载时使用默认值
        let prefs = userPreference
        // Task 12: 预计算消息快照 + 原始引用，切断 SwiftUI 对 SwiftData @Model 的观察链
        let entries = viewModel.messages.map { message in
            MessageListEntry(
                id: message.id,
                snapshot: MessageSnapshot(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    imageData: message.imageData,
                    isStreaming: false,
                    attachedImage: message.attachedImage
                ),
                original: message
            )
        }
        // 自动滚动触发值
        let scrollToken = AnyHashable(ScrollToken(
            messageCount: viewModel.messages.count,
            streamingLength: viewModel.streamingText.count,
            isLoading: viewModel.isLoading
        ))
        // 内容刷新触发值
        let refreshToken = AnyHashable(ContentRefreshToken(
            bubbleStyle: prefs?.bubbleStyle ?? "liquidGlass",
            fontSize: prefs?.fontSize ?? 16.0,
            lineHeight: prefs?.lineHeight ?? 1.5,
            avatarDataHash: prefs?.avatarData?.hashValue ?? 0,
            reduceMotion: reduceMotion,
            feedbackStatesHash: viewModel.feedbackStates.hashValue,
            speakingMessageId: viewModel.speakingMessageId
        ))

        return Group {
            if entries.isEmpty && viewModel.streamingText.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 420)
            } else {
                // Task 12: iOS 使用 UICollectionView 虚拟化，macOS 回退到 LazyVStack
                VirtualizedMessageList(
                    messages: entries,
                    autoScrollTrigger: scrollToken,
                    contentRefreshTrigger: refreshToken,
                    scrollAnimated: !reduceMotion,
                    content: { entry in
                        messageBubble(for: entry, prefs: prefs)
                    },
                    footer: {
                        footerContent
                    }
                )
            }
        }
        // v1.2: 升级为 bubbleLiquidIn 液态进出动画 token
        .animation(reduceMotion ? nil : AnimationTokens.bubbleLiquidIn, value: viewModel.messages.count)
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .animation(reduceMotion ? nil : AnimationTokens.transition, value: viewModel.feedbackToast)
        .onAppear {
            // 在 onAppear 中加载用户偏好，只创建一次 ChatStorage 实例
            userPreference = ChatStorage(modelContext: modelContext).fetchPreference()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidUpdate)) { _ in
            // 设置页关闭后重新加载用户偏好，确保气泡样式、字体大小、行距等立即生效
            userPreference = ChatStorage(modelContext: modelContext).fetchPreference()
        }
    }

    /// 渲染单条消息气泡，保留全部回调（复制 / 重新提问 / 重新生成 / 分叉 / 朗读 / 反馈）
    @ViewBuilder
    private func messageBubble(for entry: MessageListEntry, prefs: UserPreference?) -> some View {
        let message = entry.original
        MessageBubble(
            message: entry.snapshot,
            isSpeaking: viewModel.speakingMessageId == message.id,
            onToggleSpeak: {
                viewModel.toggleSpeak(messageId: message.id, content: message.content)
            },
            feedbackState: viewModel.feedbackStates[message.id],
            onFeedback: { isPositive in
                viewModel.handleFeedback(messageId: message.id, isPositive: isPositive, modelContext: modelContext)
            },
            onCopy: {
                #if os(iOS)
                UIPasteboard.general.string = message.content
                #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                #endif
                viewModel.feedbackToast = "已复制"
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    viewModel.feedbackToast = nil
                }
            },
            onResend: {
                if let conv = conversation {
                    viewModel.resendMessage(content: message.content, in: conv, modelContext: modelContext)
                }
            },
            onRegenerate: {
                // Task 23.2: 重新生成——仅 AI 消息
                if let conv = conversation, message.role == "assistant" {
                    viewModel.regenerateResponse(assistantMessage: message, in: conv, modelContext: modelContext)
                }
            },
            onBranch: {
                // Task 23.2: 从此处分叉——创建新会话并显示提示
                if let conv = conversation {
                    if let _ = viewModel.branch(from: message, in: conv, modelContext: modelContext) {
                        viewModel.feedbackToast = "已创建分叉会话"
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            viewModel.feedbackToast = nil
                        }
                    }
                }
            },
            bubbleStyle: BubbleStyleType.current(prefs?.bubbleStyle ?? "liquidGlass"),
            fontSize: prefs?.fontSize ?? 16.0,
            lineHeight: prefs?.lineHeight ?? 1.5,
            aiAvatarData: prefs?.avatarData
        )
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    /// Task 12: 底部追加内容——流式气泡、引用来源、工具调用流程、加载状态
    /// 在 iOS 上作为 UICollectionView 的最后一个 Cell 渲染；在 macOS 上追加到 LazyVStack 末尾
    @ViewBuilder
    private var footerContent: some View {
        if !viewModel.streamingText.isEmpty {
            // Day 10: 用独立 StreamingBubbleView 隔离 streamingText 渲染
            // 避免 chunk 更新触发 ForEach messages 全量重算
            StreamingBubbleView(text: viewModel.streamingText)
        }
        if !viewModel.currentCitations.isEmpty {
            VStack(spacing: Spacing.md) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.captionAI)
                        .foregroundStyle(.tertiary)
                    Text("引用来源", comment: "")
                        .font(.toolLabel)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 6)

                ForEach(Array(viewModel.currentCitations.enumerated()), id: \.offset) { idx, chunk in
                    CitationCard(citation: chunk, index: idx)
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
        if !viewModel.currentToolSteps.isEmpty {
            HStack(spacing: 6) {
                // v1.2: 使用 AetherIcon.tool 替换 SF Symbol
                AetherIcon.tool.systemImage
                    .font(.captionAI)
                    .foregroundStyle(.tertiary)
                Text("工具调用流程", comment: "")
                    .font(.toolLabel)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 6)
            .transition(.opacity)
        }

        ForEach(viewModel.currentToolSteps) { step in
            StepCardView(step: ToolStepSnapshot(
                id: step.id,
                toolName: step.toolName,
                status: convertStatus(step.status),
                result: step.result,
                thought: step.thought,
                arguments: step.arguments,
                loopIndex: step.loopIndex
            ))
        }
        if viewModel.isLoading && viewModel.streamingText.isEmpty {
            LoadingStateView(text: "AI 正在思考...")
        }
    }

    /// 反馈 Toast 浮层
    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = viewModel.feedbackToast {
            Text(toast)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, Spacing.md)
                .background(Color.black.opacity(0.75))
                .clipShape(Capsule())
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "sparkles",
            title: "以太",
            message: "你的智能助手，在下方输入消息开始对话"
        )
    }

    private func convertStatus(_ status: ChatViewModel.ToolStepStatus) -> ToolStepSnapshot.Status {
        switch status {
        case .running: return .running
        case .completed: return .completed
        case .failed: return .failed
        }
    }
}
