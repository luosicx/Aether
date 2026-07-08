import Foundation

/// Markdown 表格对齐方式
enum MarkdownTableAlignment {
    case left
    case center
    case right
}

/// Markdown 表格数据模型
struct MarkdownTable: Identifiable {
    let id = UUID()
    let headers: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
}

/// Markdown 表格解析器
enum MarkdownTableParser {

    /// 判断一行是否为表格行（以 | 开头）
    static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|")
    }

    /// 判断一行是否为对齐分隔行（如 |---|---|）
    static func isAlignmentRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        // 去掉首尾 | 后，每段应只包含 -、: 字符
        let cells = parseCells(trimmed)
        return cells.allSatisfy { cell in
            let cleaned = cell.replacingOccurrences(of: " ", with: "")
            return cleaned.allSatisfy { $0 == "-" || $0 == ":" } && cleaned.contains("-")
        }
    }

    /// 解析对齐方式
    static func parseAlignment(_ cell: String) -> MarkdownTableAlignment {
        let cleaned = cell.replacingOccurrences(of: " ", with: "")
        let hasLeft = cleaned.hasPrefix(":")
        let hasRight = cleaned.hasSuffix(":")
        if hasLeft && hasRight { return .center }
        if hasRight { return .right }
        return .left // default
    }

    /// 将一行按 | 分割为单元格（去掉首尾空管道符）
    static func parseCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        // 去掉首尾的 |
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// 从多行文本解析表格
    /// - Parameter lines: 连续的表格行（至少 2 行：表头 + 对齐行）
    /// - Returns: 解析成功返回 MarkdownTable，否则 nil
    static func parse(_ lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2 else { return nil }

        // 第一行：表头
        let headerCells = parseCells(lines[0])
        guard !headerCells.isEmpty else { return nil }

        // 第二行：对齐分隔
        guard isAlignmentRow(lines[1]) else { return nil }
        let alignmentCells = parseCells(lines[1])
        let alignments = alignmentCells.map { parseAlignment($0) }

        // 后续行：数据行
        var dataRows: [[String]] = []
        for i in 2..<lines.count {
            let cells = parseCells(lines[i])
            // 补齐列数不足的情况
            var padded = cells
            while padded.count < headerCells.count {
                padded.append("")
            }
            dataRows.append(padded)
        }

        return MarkdownTable(
            headers: headerCells,
            alignments: alignments,
            rows: dataRows
        )
    }
}
