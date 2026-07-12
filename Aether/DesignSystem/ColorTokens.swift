import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 语义颜色 token：所有视图统一使用这些扩展，不直接引用 Color.red / Color(.systemGray5)
extension Color {
    // MARK: - Aether 品牌色
    /// 深空黑/浅空白基底
    static let deepSpace = Color("DeepSpace")
    /// 神秘紫强调色
    static let aetherPurple = Color("AetherPurple")
    /// 电光蓝交互色
    static let electricBlue = Color("ElectricBlue")
    /// 液态玻璃卡片基底
    static let liquidGlass = Color("LiquidGlass")
    /// 星云光晕高光
    static let nebulaGlow = Color("NebulaGlow")
    /// 星光白/夜色文字
    static let starlight = Color("Starlight")
    /// 暮色灰（系统色 fallback）
    static var duskGray: Color {
        #if canImport(UIKit)
        return Color(.systemGray2)
        #else
        return Color(NSColor.systemGray)
        #endif
    }

    // MARK: - Aether 渐变
    /// 品牌主渐变：紫 → 电光蓝
    static var aetherGradient: LinearGradient {
        LinearGradient(colors: [aetherPurple, electricBlue],
                      startPoint: .topLeading,
                      endPoint: .bottomTrailing)
    }

    // MARK: - 背景
    /// 主背景（List / Form 默认背景）
    /// Task 25: 改为从 ThemeManager 读取当前主题的背景色，实现主题切换
    static var backgroundPrimary: Color {
        ThemeManager.shared.currentTheme.backgroundGradient.first ?? Color.black
    }
    /// 次背景（卡片 / 分组背景）
    static var backgroundSecondary: Color {
        #if canImport(UIKit)
        return Color(.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    /// 三级背景（代码块 / 输入栏）
    static var backgroundTertiary: Color {
        #if canImport(UIKit)
        return Color(.tertiarySystemBackground)
        #else
        return Color(NSColor.underPageBackgroundColor)
        #endif
    }

    // MARK: - 气泡
    /// 用户气泡背景
    /// Task 25: 从 ThemeManager 读取当前主题的用户气泡色
    static var bubbleUser: Color {
        ThemeManager.shared.currentTheme.bubbleUserColor
    }
    /// 助手气泡背景（液态玻璃基底，配合视图中 .ultraThinMaterial 使用）
    /// Task 25: 从 ThemeManager 读取当前主题的 AI 气泡色
    static var bubbleAI: Color {
        ThemeManager.shared.currentTheme.bubbleAIColor
    }

    // MARK: - 文字
    /// 主要文字
    /// Task 25: 从 ThemeManager 读取当前主题的主要文字色
    static var textPrimary: Color {
        ThemeManager.shared.currentTheme.textPrimaryColor
    }
    /// 次要文字
    /// Task 25: 从 ThemeManager 读取当前主题的次要文字色
    static var textSecondary: Color {
        ThemeManager.shared.currentTheme.textSecondaryColor
    }
    /// 三级文字（时间戳、占位）
    /// Task 25: 从主题次要色派生，保证主题切换时层次一致
    static var textTertiary: Color {
        ThemeManager.shared.currentTheme.textSecondaryColor.opacity(0.6)
    }

    // MARK: - 分隔线
    static var separator: Color {
        #if canImport(UIKit)
        return Color(.separator).opacity(0.3)
        #else
        return Color(NSColor.separatorColor).opacity(0.3)
        #endif
    }

    // MARK: - 代码块（深浅色双主题）
    /// 代码块背景（浅色）
    static let codeBackgroundLight = Color(red: 0.96, green: 0.97, blue: 0.98)
    /// 代码块背景（深色）
    static let codeBackgroundDark = Color(red: 0.16, green: 0.17, blue: 0.19)
    /// 代码块边框
    static var codeBorder: Color {
        #if canImport(UIKit)
        return Color(.systemGray5)
        #else
        return Color(NSColor.separatorColor)
        #endif
    }
}
