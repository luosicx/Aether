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

    // MARK: - v1.2 设计与体验升级

    /// 消息气泡液态进入：scale + opacity 组合，spring 0.5s damping 0.7
    /// 用于消息气泡插入时的液态出现动效
    public static let bubbleLiquidIn: Animation = .spring(response: 0.5, dampingFraction: 0.7)

    /// 消息气泡液态退出：向右滑出 + 淡出
    /// 用于消息气泡删除时的过渡
    public static let bubbleLiquidOut: Animation = .easeInOut(duration: 0.25)

    /// 微交互 spring：按钮按压 / 长按反馈 / 拖拽阴影
    /// response 0.3s damping 0.75，自然回弹手感
    public static let interactiveSpring: Animation = .spring(response: 0.3, dampingFraction: 0.75)

    /// 滚动视差：缓慢 decelerate
    public static let scrollParallax: Animation = .easeOut(duration: 0.4)

    /// 主题切换平滑过渡：0.3s easeInOut，避免色板硬切闪烁
    public static let themeSmooth: Animation = .easeInOut(duration: 0.3)

    /// 星空呼吸效果：4s 周期 phaseAnimator，修改 shadowRadius 与 opacity
    public static let starBreath: Animation = .easeInOut(duration: 4).repeatForever(autoreverses: true)

    /// 低能力设备降级动画：所有 spring 替换为快速 easeInOut
    public static let reducedMotion: Animation = .easeInOut(duration: 0.15)
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

// MARK: - v1.2: 液态过渡 AnyTransition 便捷访问

public extension AnyTransition {
    /// v1.2: 消息气泡液态进入——scale + opacity 组合
    /// 配合 `AnimationTokens.bubbleLiquidIn` 实现"Aether 式"液态出现动效
    static var bubbleLiquidIn: AnyTransition {
        .asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    /// v1.2: 主题切换过渡——平滑色板过渡，避免硬切闪烁
    /// 配合 `AnimationTokens.themeSmooth`
    static var themeSmooth: AnyTransition {
        .opacity
    }
}
