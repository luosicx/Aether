import SwiftUI

/// 通用卡片样式 modifier：统一背景、圆角、描边、阴影（深空液态玻璃风格）
struct CardStyle: ViewModifier {
    var background: Color = .liquidGlass
    var cornerRadius: CGFloat = CornerRadius.medium
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                background.opacity(0.6)
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.nebulaGlow.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: Color.aetherPurple.opacity(0.18), radius: 12, y: 4)
    }
}

extension View {
    /// 应用通用卡片样式
    func cardStyle(
        background: Color = .liquidGlass,
        cornerRadius: CGFloat = CornerRadius.medium,
        padding: CGFloat = Spacing.lg
    ) -> some View {
        modifier(CardStyle(background: background, cornerRadius: cornerRadius, padding: padding))
    }
}
