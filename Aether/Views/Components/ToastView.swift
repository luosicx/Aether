import SwiftUI

/// 统一 Toast 反馈：操作成功/复制/撤销
struct ToastView: View {
    let message: String
    var systemImage: String = "checkmark.circle.fill"

    var body: some View {
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
struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    var systemImage: String = "checkmark.circle.fill"

    func body(content: Content) -> some View {
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

extension View {
    /// 显示 Toast：自动 2 秒后消失
    func toast(isPresented: Binding<Bool>, message: String, systemImage: String = "checkmark.circle.fill") -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, systemImage: systemImage))
    }
}

#Preview {
    ToastView(message: "已复制")
        .padding()
}
