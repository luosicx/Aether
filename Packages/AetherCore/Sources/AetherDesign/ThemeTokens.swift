import SwiftUI

/// Task 25: Aether 主题枚举，定义深空 / 黎明 / 极光三套主题色板
/// rawValue 使用英文标识符，与 UserPreference.themeName 默认值 "deepSpace" 对齐
public enum AetherTheme: String, CaseIterable, Identifiable {
    /// 深空主题（默认）：深色背景 + 紫/蓝品牌色
    case deepSpace
    /// 黎明主题：暖色浅色背景 + 橙/琥珀色
    case dawn
    /// 极光主题：深绿背景 + 青绿色
    case aurora

    public var id: String { rawValue }

    /// 中文展示名称，用于设置页 Picker
    public var displayName: String {
        switch self {
        case .deepSpace: return "深空"
        case .dawn: return "黎明"
        case .aurora: return "极光"
        }
    }

    /// 主题图标（SF Symbol），用于 Picker 展示
    public var iconName: String {
        switch self {
        case .deepSpace: return "moon.stars.fill"
        case .dawn: return "sun.haze.fill"
        case .aurora: return "sparkles"
        }
    }

    /// 背景渐变色数组，用于 .background(LinearGradient)
    public var backgroundGradient: [Color] {
        switch self {
        case .deepSpace:
            return [Color(red: 0.04, green: 0.04, blue: 0.06), Color(red: 0.08, green: 0.05, blue: 0.12)]
        case .dawn:
            return [Color(red: 1.0, green: 0.96, blue: 0.90), Color(red: 1.0, green: 0.88, blue: 0.75)]
        case .aurora:
            return [Color(red: 0.02, green: 0.06, blue: 0.05), Color(red: 0.0, green: 0.12, blue: 0.10)]
        }
    }

    /// 主色调
    public var primaryColor: Color {
        switch self {
        case .deepSpace: return Color.aetherPurple
        case .dawn: return Color(red: 0.90, green: 0.40, blue: 0.20)
        case .aurora: return Color(red: 0.0, green: 0.75, blue: 0.60)
        }
    }

    /// 强调色
    public var accentColor: Color {
        switch self {
        case .deepSpace: return Color.electricBlue
        case .dawn: return Color(red: 0.95, green: 0.60, blue: 0.25)
        case .aurora: return Color(red: 0.30, green: 0.95, blue: 0.55)
        }
    }

    /// 用户气泡背景色
    public var bubbleUserColor: Color {
        switch self {
        case .deepSpace: return Color.aetherPurple
        case .dawn: return Color(red: 0.90, green: 0.50, blue: 0.30)
        case .aurora: return Color(red: 0.0, green: 0.60, blue: 0.50)
        }
    }

    /// AI 气泡背景色
    public var bubbleAIColor: Color {
        switch self {
        case .deepSpace: return Color.liquidGlass
        case .dawn: return Color(red: 0.98, green: 0.95, blue: 0.90)
        case .aurora: return Color(red: 0.08, green: 0.18, blue: 0.14)
        }
    }

    /// 主要文字颜色
    public var textPrimaryColor: Color {
        switch self {
        case .deepSpace: return Color.starlight
        case .dawn: return Color(red: 0.18, green: 0.13, blue: 0.08)
        case .aurora: return Color(red: 0.90, green: 1.0, blue: 0.93)
        }
    }

    /// 次要文字颜色
    public var textSecondaryColor: Color {
        switch self {
        case .deepSpace: return Color.starlight.opacity(0.7)
        case .dawn: return Color(red: 0.40, green: 0.33, blue: 0.25)
        case .aurora: return Color(red: 0.65, green: 0.88, blue: 0.78)
        }
    }
}

/// Task 25: 主题 token 入口，根据 themeName 字符串解析为 AetherTheme
public struct ThemeTokens {
    /// 按 themeName 解析主题，未匹配时回退到 .deepSpace
    /// - Parameter themeName: 主题名称（deepSpace / dawn / aurora）
    /// - Returns: 对应的 AetherTheme
    public static func current(_ themeName: String) -> AetherTheme {
        AetherTheme(rawValue: themeName) ?? .deepSpace
    }
}
