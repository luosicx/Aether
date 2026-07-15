import SwiftUI
import AetherDesign

/// 统一 Toast 反馈：操作成功/复制/撤销
public struct ToastView: View {
    public let message: String
    public var systemImage: String = "checkmark.circle.fill"

    public init(message: String, systemImage: String = "checkmark.circle.fill") {
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
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
public struct ToastModifier: ViewModifier {
    @Binding public var isPresented: Bool
    public let message: String
    public var systemImage: String = "checkmark.circle.fill"

    public init(isPresented: Binding<Bool>, message: String, systemImage: String = "checkmark.circle.fill") {
        self._isPresented = isPresented
        self.message = message
        self.systemImage = systemImage
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isPresented {
                ToastView(message: message, systemImage: systemImage)
                    .padding(.top, Spacing.xxl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(AnimationTokens.transition) {
                                isPresented = false
                            }
                        }
                    }
                    .accessibilityAddTraits(.isModal)
            }
        }
        .animation(AnimationTokens.transition, value: isPresented)
    }
}

public extension View {
    /// 显示 Toast：自动 2 秒后消失
    func toast(isPresented: Binding<Bool>, message: String, systemImage: String = "checkmark.circle.fill") -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, systemImage: systemImage))
    }
}

#Preview {
    ToastView(message: "已复制")
        .padding()
}
