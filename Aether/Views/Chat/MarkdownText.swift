import SwiftUI

/// Markdown 渲染组件：将文本分段为代码块、表格、任务列表与普通文本
struct MarkdownText: View {
    let content: String
    /// Task 28: 字体大小（pt），默认 16
    var fontSize: Double = 16.0
    /// Task 28: 行距倍数，默认 1.5
    var lineHeight: Double = 1.5

    /// 缓存 parseBlocks 结果的包装类（NSCache value 要求 NSObject 子类）
    private final class CachedBlocks: NSObject {
        let blocks: [MarkdownBlock]
        init(blocks: [MarkdownBlock]) {
            self.blocks = blocks
            super.init()
        }
    }

    /// 模块级 parseBlocks 缓存：speakingMessageId 变化会触发所有可见 MessageBubble 重算 body，
    /// 缓存解析结果避免重复跑正则+表格解析导致主线程卡顿。
    private static let parseCache: NSCache<NSString, CachedBlocks> = {
        let cache = NSCache<NSString, CachedBlocks>()
        cache.countLimit = 200  // 最多缓存 200 条消息的解析结果，防止内存无限增长
        return cache
    }()

    /// 命中缓存则直接返回，未命中则解析并写入缓存
    private var cachedBlocks: [MarkdownBlock] {
        let key = content as NSString
        if let cached = MarkdownText.parseCache.object(forKey: key) {
            return cached.blocks
        }
        let blocks = parseBlocks()
        MarkdownText.parseCache.setObject(CachedBlocks(blocks: blocks), forKey: key)
        return blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(cachedBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let lang, let code):
                    CodeBlockView(code: code, language: lang)
                case .text(let text):
                    if let attributed = try? AttributedString(
                        markdown: text,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
                    ) {
                        Text(attributed)
                            .font(.system(size: fontSize))
                            .lineSpacing(CGFloat(fontSize) * CGFloat(lineHeight - 1))
                            .textSelection(.enabled)
                    } else {
                        Text(text)
                            .font(.system(size: fontSize))
                            .lineSpacing(CGFloat(fontSize) * CGFloat(lineHeight - 1))
                            .textSelection(.enabled)
                    }
                case .table(let table):
                    MarkdownTableView(table: table)
                case .taskList(let items):
                    TaskListView(items: items)
                case .heading(let level, let text):
                    HeadingView(level: level, text: text)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 解析逻辑

    private enum MarkdownBlock {
        case text(String)
        case code(language: String?, code: String)
        case table(MarkdownTable)
        case taskList([TaskListItem])
        case heading(level: Int, text: String)
    }

    /// 将 Markdown 文本按 ``` 分隔为代码块段与文本段，再在文本段中识别表格和任务列表
    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let segments = content.components(separatedBy: "```")

        for (index, segment) in segments.enumerated() {
            if index % 2 == 0 {
                // 偶数索引：普通文本段——进一步解析表格和任务列表
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(contentsOf: parseTextSegment(segment))
                }
            } else {
                // 奇数索引：代码块段
                let lines = segment.components(separatedBy: "\n")
                var language: String?
                var code = segment

                if let firstLine = lines.first,
                   !firstLine.isEmpty,
                   !firstLine.contains(" ") {
                    language = firstLine.trimmingCharacters(in: .whitespaces)
                    code = lines.dropFirst().joined(separator: "\n")
                }

                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedCode.isEmpty {
                    blocks.append(.code(language: language, code: trimmedCode))
                }
            }
        }

        return blocks
    }

    /// 在文本段中识别表格行和任务列表行，拆分为多个 block
    private func parseTextSegment(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var textBuffer: [String] = []
        var taskItems: [TaskListItem] = []

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            let joined = textBuffer.joined(separator: "\n")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(joined))
            }
            textBuffer.removeAll()
        }

        func flushTaskList() {
            guard !taskItems.isEmpty else { return }
            blocks.append(.taskList(taskItems))
            taskItems.removeAll()
        }

        // 任务列表正则：- [x] 或 - [ ] 开头
        let taskPattern = #"^\s*[-*]\s+\[([xX ])\]\s+(.+)"#
        let taskRegex = try? NSRegularExpression(pattern: taskPattern, options: [.anchorsMatchLines])

        // 标题正则：# ~ ######（1-6 个 # 后接空格）
        let headingPattern = #"^\s*(#{1,6})\s+(.+)$"#
        let headingRegex = try? NSRegularExpression(pattern: headingPattern, options: [.anchorsMatchLines])

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // 检查是否为标题行（# ~ ######）
            if let match = headingRegex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               match.numberOfRanges >= 3,
               let levelRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                flushText()
                flushTaskList()
                let level = line[levelRange].count  // # 的数量即为标题层级
                let headingText = String(line[textRange])
                blocks.append(.heading(level: level, text: headingText))
                i += 1
                continue
            }

            // 检查是否为任务列表项
            if let regex = taskRegex,
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               match.numberOfRanges >= 3,
               let checkRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                flushText()
                let checkChar = line[checkRange]
                let isCompleted = checkChar == "x" || checkChar == "X"
                let taskText = String(line[textRange])
                taskItems.append(TaskListItem(isCompleted: isCompleted, text: taskText))
                i += 1
                continue
            } else {
                // 非任务列表行——如果之前有任务列表项，先 flush
                if !taskItems.isEmpty {
                    flushTaskList()
                }
            }

            // 检查是否为表格行
            if MarkdownTableParser.isTableRow(line) {
                // 收集连续表格行
                var tableLines: [String] = []
                while i < lines.count && MarkdownTableParser.isTableRow(lines[i]) {
                    tableLines.append(lines[i])
                    i += 1
                }
                if let table = MarkdownTableParser.parse(tableLines) {
                    flushText()
                    blocks.append(.table(table))
                } else {
                    // 解析失败，当作普通文本
                    textBuffer.append(contentsOf: tableLines)
                }
                continue
            }

            // 普通文本行
            textBuffer.append(line)
            i += 1
        }

        // flush 残余
        flushTaskList()
        flushText()

        return blocks
    }
}
