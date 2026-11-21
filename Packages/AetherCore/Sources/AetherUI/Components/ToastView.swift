import SwiftUI
import AetherDesign

/// 统一 Toast 反馈：操作成功/复制/撤销/失败
public struct ToastView: View {
    public let message: String
    public var systemImage: String = "checkmark.circle.fill"
    public var tint: Color = .green

    public init(
        message: String,
        systemImage: String = "checkmark.circle.fill",
        tint: Color = .green
    ) {
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadlineAI)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.black.opacity(0.75))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// Toast overlay modifier
///
/// 注意：这里刻意不加 `.isModal` 无障碍特征。Toast 只是瞬时反馈，标记为 modal 会让
/// VoiceOver 在弹出期间把整屏其它控件当作不可达，也会让 XCUITest 在同屏查询里找不到它们。
public struct ToastModifier: ViewModifier {
    @Binding public var isPresented: Bool
    public let message: String
    public var systemImage: String = "checkmark.circle.fill"
    public var tint: Color = .green
    public var accessibilityID: String = ""
    public var duration: TimeInterval = 2.0

    public init(
        isPresented: Binding<Bool>,
        message: String,
        systemImage: String = "checkmark.circle.fill",
        tint: Color = .green,
        accessibilityID: String = "",
        duration: TimeInterval = 2.0
    ) {
        self._isPresented = isPresented
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.accessibilityID = accessibilityID
        self.duration = duration
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isPresented {
                ToastView(message: message, systemImage: systemImage, tint: tint)
                    .padding(.top, Spacing.xxl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation(AnimationTokens.transition) {
                                isPresented = false
                            }
                        }
                    }
                    .accessibilityIdentifier(accessibilityID)
            }
        }
        .animation(AnimationTokens.transition, value: isPresented)
    }
}

public extension View {
    /// 显示 Toast：默认 2 秒后消失
    func toast(
        isPresented: Binding<Bool>,
        message: String,
        systemImage: String = "checkmark.circle.fill",
        tint: Color = .green,
        accessibilityID: String = "",
        duration: TimeInterval = 2.0
    ) -> some View {
        modifier(ToastModifier(
            isPresented: isPresented,
            message: message,
            systemImage: systemImage,
            tint: tint,
            accessibilityID: accessibilityID,
            duration: duration
        ))
    }
}

#Preview {
    ToastView(message: "已复制")
        .padding()
}
