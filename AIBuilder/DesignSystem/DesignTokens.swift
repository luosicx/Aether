import SwiftUI

/// AIBuilder 设计系统入口：聚合颜色、字体、间距、圆角、动画 token
/// 使用方式：Color.backgroundPrimary / Font.bodyAI / Spacing.medium / AnimationTokens.transition
enum DesignTokens {}

/// 间距 token（基于 4pt grid）
enum Spacing {
    /// 2pt
    static let xs: CGFloat = 2
    /// 4pt
    static let sm: CGFloat = 4
    /// 8pt
    static let md: CGFloat = 8
    /// 12pt
    static let lg: CGFloat = 12
    /// 16pt
    static let xl: CGFloat = 16
    /// 24pt
    static let xxl: CGFloat = 24
    /// 32pt
    static let xxxl: CGFloat = 32
}

/// 圆角 token（适配液态玻璃圆润感）
enum CornerRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let pill: CGFloat = 999
}

/// 动画 token
enum AnimationTokens {
    /// 页面转场 0.25s
    static let transition: Animation = .easeInOut(duration: 0.25)
    /// 消息进入 0.2s
    static let messageAppear: Animation = .easeOut(duration: 0.2)
    /// 按钮按下 0.1s
    static let buttonPress: Animation = .easeInOut(duration: 0.1)
    /// 骨架屏呼吸 0.8s
    static let skeleton: Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    /// 闪烁光标 0.5s
    static let blink: Animation = .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
}
