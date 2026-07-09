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

    var body: some View {
        ScrollViewReader { proxy in
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
                            }
                        )
                            .id(message.id.uuidString)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
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
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                    withAnimation(.easeOut(duration: 0.2)) {
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
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.feedbackToast)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            // 视觉锚点：渐变光晕的圆形图标
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }

            VStack(spacing: Spacing.md) {
                Text("AI Builder")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text("你的智能助手")
                    .font(.bodyAI)
                    .foregroundStyle(.secondary)
            }

            Text("在下方输入消息，或点击右上角设置 API Key")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private func convertStatus(_ status: ChatViewModel.ToolStepStatus) -> ToolStepSnapshot.Status {
        switch status {
        case .running: return .running
        case .completed: return .completed
        case .failed: return .failed
        }
    }
}
