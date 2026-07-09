import SwiftUI

/// 消息值类型快照：用于切断 SwiftUI 对 SwiftData @Model 的观察链
struct MessageSnapshot: Identifiable, Equatable {
    let id: UUID
    let role: String
    let content: String
    let imageData: Data?
    let isStreaming: Bool
    /// Day 5 补充A：用户从相册附带的图片
    let attachedImage: Data?
}

/// 跨平台从 Data 创建 SwiftUI Image(iOS: UIImage / macOS: NSImage)
private func platformImage(from data: Data) -> Image? {
    #if os(iOS)
    guard let img = UIImage(data: data) else { return nil }
    return Image(uiImage: img)
    #else
    guard let img = NSImage(data: data) else { return nil }
    return Image(nsImage: img)
    #endif
}

#if os(macOS)
/// macOS 下补齐 iOS UIKit 语义色,使 `Color(.systemGray5)` / `Color(.separator)` 等写法跨平台可用
/// 三色按 iOS 灰阶递进映射,保证 systemGray3(深) > systemGray5(中) > systemGray6(浅) 层次可区分:
/// - systemGray3 → separatorColor: 较深灰, 用于分隔线/禁用态按钮
/// - systemGray5 → textBackgroundColor: 中灰, 用于表格表头/StreamingBubbleView/卡片背景
/// - systemGray6 → controlBackgroundColor: 较浅灰, 用于交替行/气泡背景/输入栏
extension NSColor {
    static var systemGray3: NSColor { .separatorColor }
    static var systemGray5: NSColor { .textBackgroundColor }
    static var systemGray6: NSColor { .controlBackgroundColor }
    static var separator: NSColor { .separatorColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
}
#endif

/// 跨平台 ToolbarItem 位置: iOS 用 .topBarTrailing/.topBarLeading, macOS 用 .primaryAction/.automatic
extension ToolbarItemPlacement {
    static var topBarTrailingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }
    static var topBarLeadingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .automatic
        #endif
    }
}

struct MessageBubble: View {
    let message: MessageSnapshot
    let isSpeaking: Bool
    let onToggleSpeak: () -> Void
    /// Day 12: 当前已记录的反馈状态（nil=未反馈 / true=赞 / false=踩）
    let feedbackState: Bool?
    /// Day 12: 点击反馈按钮的回调，参数为新选择的反馈值
    let onFeedback: (Bool) -> Void
    /// 复制消息内容回调
    let onCopy: () -> Void
    /// 重新提问回调（仅用户消息）
    let onResend: () -> Void
    /// Day 5 补充A：控制全屏图片预览
    @State private var showFullScreenImage = false

    init(message: MessageSnapshot,
         isSpeaking: Bool = false,
         onToggleSpeak: @escaping () -> Void = {},
         feedbackState: Bool? = nil,
         onFeedback: @escaping (Bool) -> Void = { _ in },
         onCopy: @escaping () -> Void = {},
         onResend: @escaping () -> Void = {}) {
        self.message = message
        self.isSpeaking = isSpeaking
        self.onToggleSpeak = onToggleSpeak
        self.feedbackState = feedbackState
        self.onFeedback = onFeedback
        self.onCopy = onCopy
        self.onResend = onResend
    }

    private var isUser: Bool { message.role == "user" }
    private var isTool: Bool { message.role == "tool" }
    private var isAssistant: Bool { message.role == "assistant" }
    private var canSpeak: Bool { isAssistant && !message.content.isEmpty && !message.isStreaming }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if isUser { Spacer(minLength: 48) }
            if !isUser {
                AvatarView(role: .assistant, size: 28)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.sm) {
                if isTool {
                    Text("工具调用")
                        .font(.toolLabel)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                content
                if let imageData = message.imageData, let img = platformImage(from: imageData) {
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if canSpeak {
                    Button(action: onToggleSpeak) {
                        Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.captionAI)
                            .foregroundStyle(isSpeaking ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSpeaking ? "停止朗读" : "朗读")
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, 2)
                }
                if isAssistant && !message.content.isEmpty && !message.isStreaming {
                    FeedbackBar(isPositive: feedbackState, onFeedback: onFeedback)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, 2)
                }
            }
            if isUser {
                AvatarView(role: .user, size: 28)
            }
            if !isUser { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isTool {
            HStack(spacing: 6) {
                Rectangle()
                    #if os(iOS)
                    .fill(Color.textTertiary.opacity(0.3))
                    #else
                    .fill(Color.secondary.opacity(0.3))
                    #endif
                    .frame(width: 2)
                Text(message.content)
                    .font(.monoAI)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Day 5 补充A：user 气泡显示附带图片缩略图（位于文字上方，点击全屏预览）
                if let imageData = message.attachedImage, let img = platformImage(from: imageData) {
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("用户发送的图片，点击查看全屏")
                        .onTapGesture { showFullScreenImage = true }
                        #if os(iOS)
                        .fullScreenCover(isPresented: $showFullScreenImage) {
                            fullScreenImageContent(img: img)
                        }
                        #else
                        .sheet(isPresented: $showFullScreenImage) {
                            fullScreenImageContent(img: img)
                        }
                        #endif
                }
                HStack(alignment: .bottom, spacing: 0) {
                    if isAssistant {
                        MarkdownText(content: message.content)
                        if message.isStreaming {
                            Text("▍")
                                .foregroundStyle(.tertiary)
                                .modifier(BlinkingCursor())
                        }
                    } else {
                        Text(message.content)
                        if message.isStreaming {
                            Text("▍")
                                .foregroundStyle(.tertiary)
                                .modifier(BlinkingCursor())
                        }
                    }
                }
            }
            .font(.bodyAI)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(bubbleBackground)
            .foregroundStyle(isUser ? Color.white : Color.textPrimary)
            .clipShape(bubbleShape)
            // Day 19: 无障碍——合并气泡内文本与光标为一个元素，用完整消息文本作为朗读值
            .accessibilityElement(children: .combine)
            .accessibilityValue(message.content)
            .contextMenu {
                if !message.isStreaming {
                    Button {
                        onCopy()
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    if isUser {
                        Button {
                            onResend()
                        } label: {
                            Label("重新提问", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    private var bubbleBackground: Color {
        isUser ? Color.bubbleUser : Color.bubbleAssistant
    }

    private var bubbleShape: some Shape {
        #if os(iOS)
        let corners: UIRectCorner = isUser
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]
        return RoundedCornerShape(radius: CornerRadius.large, corners: corners)
        #else
        return UnevenRoundedRectangle(
            cornerRadii: isUser
                ? .init(topLeading: CornerRadius.large, bottomLeading: CornerRadius.large, bottomTrailing: 0, topTrailing: CornerRadius.large)
                : .init(topLeading: CornerRadius.large, bottomLeading: 0, bottomTrailing: CornerRadius.large, topTrailing: CornerRadius.large)
        )
        #endif
    }

    /// 全屏图片预览内容（iOS 用 fullScreenCover / macOS 用 sheet）
    @ViewBuilder
    private func fullScreenImageContent(img: Image) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            img
                .resizable()
                .scaledToFit()
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullScreenImage = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .padding()
                    }
                    .accessibilityLabel("关闭全屏图片")
                }
                Spacer()
            }
        }
    }
}

#if os(iOS)
struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}
#endif

struct BlinkingCursor: ViewModifier {
    @State private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(visible ? 1 : 0)
                .onAppear {
                    withAnimation(AnimationTokens.blink) {
                        visible = false
                    }
                }
        }
    }
}
