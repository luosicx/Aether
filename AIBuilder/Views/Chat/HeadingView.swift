import SwiftUI

/// Markdown 标题分级渲染组件：根据级别（1-6）应用不同字号、字重与间距。
struct HeadingView: View {
    let level: Int
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(attributedText)
                .font(font)
                .textSelection(.enabled)
            // H1 与 H2 下方追加分割线以增强视觉层级
            if level <= 2 {
                Divider()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 样式

    /// 根据标题级别返回对应字号与字重
    private var font: Font {
        switch level {
        case 1:
            return .title.weight(.bold)
        case 2:
            return .title2.weight(.bold)
        case 3:
            return .title3.weight(.semibold)
        default:
            // H4-H6 统一使用 body 字号
            return .body.weight(.semibold)
        }
    }

    // MARK: - 文本解析

    /// 解析内联 Markdown（粗体、斜体、链接、行内代码）；解析失败则回退为纯文本
    private var attributedText: AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
        ) {
            return attributed
        }
        return AttributedString(text)
    }
}
