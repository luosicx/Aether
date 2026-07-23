import SwiftUI

/// Aether 设计系统入口：聚合颜色、字体、间距、圆角、动画 token
/// 使用方式：Color.backgroundPrimary / Font.bodyAI / Spacing.medium / AnimationTokens.transition
public enum DesignTokens {}

/// 间距 token（基于 4pt grid）
public enum Spacing {
    /// 2pt
    public static let xs: CGFloat = 2
    /// 4pt
    public static let sm: CGFloat = 4
    /// 8pt
    public static let md: CGFloat = 8
    /// 12pt
    public static let lg: CGFloat = 12
    /// 16pt
    public static let xl: CGFloat = 16
    /// 24pt
    public static let xxl: CGFloat = 24
    /// 32pt
    public static let xxxl: CGFloat = 32
}

/// 圆角 token（适配液态玻璃圆润感）
public enum CornerRadius {
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let pill: CGFloat = 999
}

/// 动画 token
public enum AnimationTokens {
    /// 页面转场 0.25s
    public static let transition: Animation = .easeInOut(duration: 0.25)
    /// 消息气泡进出场（spring 0.3s）
    public static let messageBubble: Animation = .spring(duration: 0.3)
    /// 消息进入 0.2s（保留用于轻量淡入场景）
    public static let messageAppear: Animation = .easeOut(duration: 0.2)
    /// 主题切换过渡 0.4s
    public static let themeTransition: Animation = .easeInOut(duration: 0.4)
    /// sheet 过渡（spring 0.35s）
    public static let sheetPresentation: Animation = .spring(duration: 0.35)
    /// 列表项过渡 0.25s
    public static let listItemTransition: Animation = .easeInOut(duration: 0.25)
    /// 按钮按下 0.1s
    public static let buttonPress: Animation = .easeInOut(duration: 0.1)
    /// 骨架屏呼吸 0.8s
    public static let skeleton: Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    /// 闪烁光标 0.5s
    public static let blink: Animation = .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
    /// v1.1 Phase D: 星空漂移 60s（线性循环，粒子横向缓慢移动）
    public static let starDrift: Animation = .linear(duration: 60).repeatForever(autoreverses: false)
    /// v1.1 Phase D: 星点闪烁 2s（easeInOut 来回呼吸）
    public static let twinkle: Animation = .easeInOut(duration: 2).repeatForever(autoreverses: true)
}

/// 按钮按压反馈样式：按下时缩小到 0.92，使用 AnimationTokens.buttonPress 动画
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(AnimationTokens.buttonPress, value: configuration.isPressed)
    }
}
