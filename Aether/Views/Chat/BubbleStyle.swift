import SwiftUI
import AetherDesign

/// Task 27: 对话气泡样式枚举
/// rawValue 与 UserPreference.bubbleStyle 对齐
enum BubbleStyleType: String, CaseIterable, Identifiable {
    /// 液态玻璃（默认）：毛玻璃 + 渐变描边
    case liquidGlass
    /// 极简：无边框无背景
    case minimal
    /// 卡片：带边框和阴影
    case card

    var id: String { rawValue }

    /// 中文展示名称
    var displayName: String {
        switch self {
        case .liquidGlass: return "液态玻璃"
        case .minimal: return "极简"
        case .card: return "卡片"
        }
    }

    /// SF Symbol 图标
    var iconName: String {
        switch self {
        case .liquidGlass: return "circle.lefthalf.filled"
        case .minimal: return "line.3.horizontal"
        case .card: return "rectangle.stack.fill"
        }
    }

    /// 按 bubbleStyle 字符串解析样式，未匹配时回退到 .liquidGlass
    /// - Parameter styleName: 样式名（liquidGlass / minimal / card）
    /// - Returns: 对应的 BubbleStyleType
    static func current(_ styleName: String) -> BubbleStyleType {
        BubbleStyleType(rawValue: styleName) ?? .liquidGlass
    }
}

/// Task 27: 气泡样式修饰器，根据 style 与 isUser 应用不同的背景/边框/阴影
/// 在 MessageBubble 中通过 .modifier(BubbleStyleModifier(...)) 应用
/// 注意：clipShape 由 MessageBubble 单独应用，修饰器仅负责背景/描边/阴影
struct BubbleStyleModifier: ViewModifier {
    let style: BubbleStyleType
    let isUser: Bool
    // 通过 @Environment 注入主题管理器，避免直接访问单例
    @Environment(ThemeManager.self) private var themeManager

    func body(content: Content) -> some View {
        switch style {
        case .liquidGlass:
            // 液态玻璃：毛玻璃基底 + 主题气泡色 + AI 渐变描边
            content
                .background(
                    (isUser ? Color.bubbleUser.opacity(0.85) : Color.bubbleAI.opacity(0.75))
                        .background(.ultraThinMaterial)
                )
                .overlay {
                    if !isUser {
                        // AI 气泡紫-蓝渐变描边
                        RoundedRectangle(cornerRadius: CornerRadius.large)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.aetherPurple, Color.electricBlue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .opacity(0.6)
                    }
                }
                .shadow(color: isUser ? .clear : Color.nebulaGlow.opacity(0.3), radius: 10)
        case .minimal:
            // 极简：无边框无背景，仅保留内容
            content
                .background(Color.clear)
                .shadow(color: .clear, radius: 0)
        case .card:
            // 卡片：主题色填充 + 主题色描边 + 阴影
            content
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.large)
                        .fill(isUser
                              ? themeManager.currentTheme.bubbleUserColor.opacity(0.2)
                              : themeManager.currentTheme.bubbleAIColor.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.large)
                        .stroke(themeManager.currentTheme.primaryColor.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
        }
    }
}
