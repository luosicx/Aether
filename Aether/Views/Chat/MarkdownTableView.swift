import SwiftUI

/// Markdown 表格渲染视图
struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GeometryReader { geometry in
                let columnCount = max(table.headers.count, 1)
                let dynamicMinWidth: CGFloat = max(geometry.size.width / CGFloat(columnCount), 60)
                VStack(alignment: .leading, spacing: 0) {
                    // 表头
                    HStack(spacing: 0) {
                        ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                            let alignment = index < table.alignments.count ? table.alignments[index] : .left
                            cellView(text: header, alignment: alignment, isHeader: true)
                                .frame(minWidth: dynamicMinWidth)
                        }
                    }
                    .background(Color.backgroundSecondary)

                    // 数据行
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                                let alignment = colIndex < table.alignments.count ? table.alignments[colIndex] : .left
                                cellView(text: cell, alignment: alignment, isHeader: false)
                                    .frame(minWidth: dynamicMinWidth)
                            }
                        }
                        .background(rowIndex % 2 == 0 ? Color.clear : Color.backgroundTertiary.opacity(0.5))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.separator, lineWidth: 0.5)
                )
            }
            .frame(minHeight: 44) // 为 GeometryReader 提供最小高度，避免布局崩溃
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("表格，%d 列 %d 行", comment: ""), table.headers.count, table.rows.count)))
    }

    /// 渲染单个单元格
    @ViewBuilder
    private func cellView(text: String, alignment: MarkdownTableAlignment, isHeader: Bool) -> some View {
        let frameAlignment: Alignment = {
            switch alignment {
            case .left: return .leading
            case .center: return .center
            case .right: return .trailing
            }
        }()

        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
        ) {
            Text(attributed)
                .font(isHeader ? .caption.weight(.semibold) : .captionAI)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        } else {
            Text(text)
                .font(isHeader ? .caption.weight(.semibold) : .captionAI)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }
}
