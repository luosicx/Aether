import SwiftUI

/// 代码块视图：深色背景 / 语法高亮 / 等宽字体 / 圆角 / 横向滚动
struct CodeBlockView: View {
    let code: String
    let language: String?

    /// 语法高亮后的属性字符串
    private var highlightedText: AttributedString {
        CodeSyntaxHighlighter.highlight(
            code.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language
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
                .background(Color(red: 0.16, green: 0.17, blue: 0.19))
            }
            // 代码内容
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(red: 0.12, green: 0.13, blue: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.map { "\($0.capitalized) 代码块" } ?? "代码块")
        .accessibilityValue(code)
    }
}
