import SwiftUI

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
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if viewModel.messages.isEmpty && viewModel.streamingText.isEmpty {
                        emptyState
                            .frame(minHeight: 420)
                    }
                    ForEach(viewModel.messages) { message in
                        let snapshot = MessageSnapshot(
                            id: message.id,
                            role: message.role,
                            content: message.content,
                            imageData: message.imageData,
                            isStreaming: false,
                            attachedImage: message.attachedImage
                        )
                        MessageBubble(
                            message: snapshot,
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
                            .id(message.id.uuidString)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    if !viewModel.streamingText.isEmpty {
                        // Day 10: 用独立 StreamingBubbleView 隔离 streamingText 渲染
                        // 避免 chunk 更新触发 ForEach messages 全量重算
                        StreamingBubbleView(text: viewModel.streamingText)
                            .id("streaming")
                    }
                    if !viewModel.currentCitations.isEmpty {
                        VStack(spacing: Spacing.md) {
                            HStack(spacing: 6) {
                                Image(systemName: "text.quote")
                                    .font(.captionAI)
                                    .foregroundStyle(.tertiary)
                                Text("引用来源")
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
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.captionAI)
                                .foregroundStyle(.tertiary)
                            Text("工具调用流程")
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
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .animation(reduceMotion ? nil : AnimationTokens.messageAppear, value: viewModel.messages.count)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: viewModel.messages.count) {
                if reduceMotion {
                    if let lastId = viewModel.messages.last?.id {
                        proxy.scrollTo(lastId.uuidString, anchor: .bottom)
                    } else {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                } else {
                    withAnimation(AnimationTokens.messageAppear) {
                        if let lastId = viewModel.messages.last?.id {
                            proxy.scrollTo(lastId.uuidString, anchor: .bottom)
                        } else {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: viewModel.streamingText) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .overlay(alignment: .bottom) {
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
            .animation(reduceMotion ? nil : AnimationTokens.transition, value: viewModel.feedbackToast)
        }
        .onAppear {
            // 在 onAppear 中加载用户偏好，只创建一次 ChatStorage 实例
            userPreference = ChatStorage(modelContext: modelContext).fetchPreference()
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
