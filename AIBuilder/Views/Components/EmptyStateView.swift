import SwiftUI

/// 统一空状态组件：插画 + 标题 + 说明 + 主操作按钮
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryButtonTitle: String?
    var primaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Color.nebulaGlow)
                .shadow(color: Color.nebulaGlow.opacity(0.6), radius: 16, y: 0)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.aetherTitle)
                    .foregroundStyle(Color.starlight)
                Text(message)
                    .font(.aetherBody)
                    .foregroundStyle(Color.duskGray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xxxl)

            if let title = primaryButtonTitle, let action = primaryAction {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.aetherPurple)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(message)")
    }
}

#Preview {
    EmptyStateView(
        systemImage: "bubble.left.and.bubble.right",
        title: "还没有对话",
        message: "点击右上角新建对话开始聊天",
        primaryButtonTitle: "新建对话",
        primaryAction: {}
    )
}
