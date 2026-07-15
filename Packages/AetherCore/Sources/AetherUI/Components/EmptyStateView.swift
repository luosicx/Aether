import SwiftUI
import AetherDesign

/// 统一空状态组件：插画 + 标题 + 说明 + 主操作按钮
public struct EmptyStateView: View {
    public let systemImage: String
    public let title: String
    public let message: String
    public var primaryButtonTitle: String?
    public var primaryAction: (() -> Void)?

    public init(systemImage: String, title: String, message: String, primaryButtonTitle: String? = nil, primaryAction: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.primaryAction = primaryAction
    }

    public var body: some View {
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
