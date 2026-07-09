import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 语义颜色 token：所有视图统一使用这些扩展，不直接引用 Color.red / Color(.systemGray5)
extension Color {
    // MARK: - 背景
    /// 主背景（List / Form 默认背景）
    static var backgroundPrimary: Color {
        #if canImport(UIKit)
        return Color(.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
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
    static let bubbleUser = Color.accentColor
    /// 助手气泡背景
    static var bubbleAssistant: Color {
        #if canImport(UIKit)
        return Color(.systemGray6)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    // MARK: - 文字
    /// 主要文字
    static var textPrimary: Color {
        #if canImport(UIKit)
        return Color(.label)
        #else
        return Color(NSColor.labelColor)
        #endif
    }
    /// 次要文字
    static var textSecondary: Color {
        #if canImport(UIKit)
        return Color(.secondaryLabel)
        #else
        return Color(NSColor.secondaryLabelColor)
        #endif
    }
    /// 三级文字（时间戳、占位）
    static var textTertiary: Color {
        #if canImport(UIKit)
        return Color(.tertiaryLabel)
        #else
        return Color(NSColor.tertiaryLabelColor)
        #endif
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
