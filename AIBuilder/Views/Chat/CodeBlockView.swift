import SwiftUI

/// 代码块视图：深浅色双主题 / 语法高亮 / 等宽字体 / 圆角 / 横向滚动
struct CodeBlockView: View {
    let code: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme

    /// 当前主题（跟随系统深浅色）
    private var theme: SyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }

    /// 代码块背景（跟随系统深浅色）
    private var background: Color {
        colorScheme == .dark ? Color.codeBackgroundDark : Color.codeBackgroundLight
    }

    /// 语法高亮后的属性字符串
    private var highlightedText: AttributedString {
        CodeSyntaxHighlighter.highlight(
            code.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            theme: theme
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 语言标签栏（有语言时显示）
            if let language, !language.isEmpty {
                HStack {
                    Text(language.capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(red: 0.62, green: 0.65, blue: 0.70))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(background)
            }
            // 代码内容
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .cardStyle(background: Color.backgroundTertiary, cornerRadius: CornerRadius.medium, padding: Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(language.map { String(format: NSLocalizedString("%@ 代码块", comment: ""), $0.capitalized) } ?? NSLocalizedString("代码块", comment: "")))
        .accessibilityValue(code)
    }
}
