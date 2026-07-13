import SwiftUI

/// Task 22: 富媒体结构化卡片——不同类型使用不同颜色和图标展示。
/// 支持 info / warning / success / error / code 五种类型。
struct RichMessageCard: View {
    /// 卡片标题
    let title: String
    /// 卡片正文内容
    let content: String
    /// 卡片类型
    let type: CardType

    /// 卡片类型枚举
    enum CardType {
        case info
        case warning
        case success
        case error
        case code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 标题行（图标 + 标题）
            HStack(spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .font(.bodyAI)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.bodyAI.weight(.semibold))
                    .foregroundStyle(textColor)
            }

            // 正文内容
            if !content.isEmpty {
                Group {
                    if type == .code {
                        // code 类型使用等宽字体
                        Text(content)
                            .font(.monoAI)
                    } else {
                        Text(content)
                            .font(.bodyAI)
                    }
                }
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .fill(backgroundColor)
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(typeLabel)：\(title)")
        .accessibilityValue(content)
    }

    // MARK: - 类型样式映射

    /// 图标名称
    private var iconName: String {
        switch type {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// 图标颜色
    private var iconColor: Color {
        switch type {
        case .info:
            return Color.electricBlue
        case .warning:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        case .code:
            return Color.aetherPurple
        }
    }

    /// 文字颜色
    private var textColor: Color {
        Color.textPrimary
    }

    /// 背景颜色
    private var backgroundColor: Color {
        switch type {
        case .info:
            return Color.electricBlue.opacity(0.1)
        case .warning:
            return Color.orange.opacity(0.1)
        case .success:
            return Color.green.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        case .code:
            return Color.aetherPurple.opacity(0.08)
        }
    }

    /// 边框颜色
    private var borderColor: Color {
        iconColor.opacity(0.3)
    }

    /// 无障碍类型标签
    private var typeLabel: String {
        switch type {
        case .info:
            return "信息"
        case .warning:
            return "警告"
        case .success:
            return "成功"
        case .error:
            return "错误"
        case .code:
            return "代码"
        }
    }
}
