import SwiftUI

/// Markdown 表格渲染视图
struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 表头
                HStack(spacing: 0) {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        let alignment = index < table.alignments.count ? table.alignments[index] : .left
                        cellView(text: header, alignment: alignment, isHeader: true)
                            .frame(minWidth: 80)
                    }
                }
                .background(Color(.systemGray5))

                // 数据行
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            let alignment = colIndex < table.alignments.count ? table.alignments[colIndex] : .left
                            cellView(text: cell, alignment: alignment, isHeader: false)
                                .frame(minWidth: 80)
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.clear : Color(.systemGray6).opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
        }
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
                .font(isHeader ? .caption.weight(.semibold) : .caption)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        } else {
            Text(text)
                .font(isHeader ? .caption.weight(.semibold) : .caption)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }
}
