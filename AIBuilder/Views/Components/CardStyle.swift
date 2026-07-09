import SwiftUI

/// 通用卡片样式 modifier：统一背景、圆角、描边、阴影
struct CardStyle: ViewModifier {
    var background: Color = .backgroundSecondary
    var cornerRadius: CGFloat = CornerRadius.medium
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.separator, lineWidth: 0.5)
            )
    }
}

extension View {
    /// 应用通用卡片样式
    func cardStyle(
        background: Color = .backgroundSecondary,
        cornerRadius: CGFloat = CornerRadius.medium,
        padding: CGFloat = Spacing.lg
    ) -> some View {
        modifier(CardStyle(background: background, cornerRadius: cornerRadius, padding: padding))
    }
}
