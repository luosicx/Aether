import Foundation
import PDFKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Task 15: 对话导出服务，支持 Markdown / PDF / DeepLink 分享链接导出。
/// 跨平台实现：iOS 使用 `UIMarkupTextPrintFormatter` + `UIGraphicsPDFRenderer`，
/// macOS 使用 `NSAttributedString(html:)` + `NSPrintOperation` 输出到临时 PDF 文件。
@MainActor
final class ConversationExporter {
    /// 日期格式化器（中文格式）
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    /// 导出为 Markdown 文本
    /// - Parameter conversation: 待导出的会话
    /// - Returns: 符合 Task 15.3 格式规范的 Markdown 字符串
    func exportAsMarkdown(conversation: Conversation) -> String {
        let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        // 构建 toolCallId -> 工具结果 的映射（tool 角色消息的 content 即工具结果）
        var toolResults: [String: String] = [:]
        for msg in sortedMessages where msg.role == "tool" {
            if let callId = msg.toolCallId {
                toolResults[callId] = msg.content
            }
        }
        // 记录已被 assistant 工具调用块消费的 tool 消息 ID，避免结果重复输出
        var consumedToolMessageIds: Set<UUID> = []

        var markdown = ""
        // 文件头元信息
        markdown += "# \(conversation.title)\n\n"
        markdown += "创建时间: \(dateFormatter.string(from: conversation.createdAt))\n"
        markdown += "消息数: \(sortedMessages.count)\n\n"
        markdown += "---\n"

        for msg in sortedMessages {
            // 跳过已被工具调用块消费的 tool 结果消息
            if msg.role == "tool" && consumedToolMessageIds.contains(msg.id) { continue }

            let roleDisplay = roleDisplayName(msg.role)
            let timeStr = dateFormatter.string(from: msg.timestamp)
            markdown += "\n### \(roleDisplay) - \(timeStr)\n\n"
            if !msg.content.isEmpty {
                markdown += "\(msg.content)\n\n"
            }

            // 工具调用块（assistant 触发的工具调用，附带参数与结果）
            if msg.role == "assistant", let calls = decodeToolCalls(from: msg) {
                for call in calls {
                    let result = toolResults[call.id] ?? "(无结果)"
                    markdown += "> 🔧 **工具调用**: \(call.name)\n"
                    markdown += "> 参数: \(call.arguments)\n"
                    markdown += "> 结果: \(result)\n"
                    // 标记对应的 tool 消息为已消费
                    if let toolMsg = sortedMessages.first(where: { $0.role == "tool" && $0.toolCallId == call.id }) {
                        consumedToolMessageIds.insert(toolMsg.id)
                    }
                }
                markdown += "\n"
            }

            // 引用块：ChatMessage 未持久化 citations（引用为瞬态数据，仅存于 ViewModel），
            // 故此处传入空数组不输出。保留格式逻辑以备后续扩展。
            appendCitations(to: &markdown, citations: [])

            markdown += "---\n"
        }
        return markdown
    }

    /// 导出为 PDF Data
    /// - Parameter conversation: 待导出的会话
    /// - Returns: PDF 二进制数据；生成失败返回 nil
    func exportAsPDF(conversation: Conversation) async -> Data? {
        let markdown = exportAsMarkdown(conversation: conversation)
        let html = Self.markdownToHTML(markdown)
        #if os(iOS)
        return Self.renderPdfIOS(html: html)
        #else
        return Self.renderPdfMacOS(html: html)
        #endif
    }

    /// 生成分享链接（DeepLink URL，如 aether://conversation/{uuid}）
    /// - Parameter conversation: 待分享的会话
    /// - Returns: DeepLink URL；构造失败返回 nil
    func exportAsShareLink(conversation: Conversation) -> URL? {
        URL(string: "aether://conversation/\(conversation.id.uuidString)")
    }

    // MARK: - Markdown 格式化辅助

    /// 将角色标识映射为中文显示名
    private func roleDisplayName(_ role: String) -> String {
        switch role {
        case "system": return "系统"
        case "user": return "用户"
        case "assistant": return "助手"
        case "tool": return "工具"
        default: return role
        }
    }

    /// 从 toolCallData（JSON）反序列化工具调用列表
    private func decodeToolCalls(from message: ChatMessage) -> [StoredToolCall]? {
        guard let data = message.toolCallData else { return nil }
        return try? JSONDecoder().decode([StoredToolCall].self, from: data)
    }

    /// 持久化的工具调用结构（与 ChatMessage.toolCallData 的 JSON 结构一致）
    private struct StoredToolCall: Codable {
        let id: String
        let type: String
        let name: String
        let arguments: String
    }

    /// 追加引用分块到 Markdown。citations 为空时不输出。
    /// - Parameters:
    ///   - markdown: 已生成的 Markdown（inout 追加）
    ///   - citations: 引用元组数组 (documentTitle, similarityScore)
    private func appendCitations(to markdown: inout String, citations: [(title: String, score: Double)]) {
        guard !citations.isEmpty else { return }
        for citation in citations {
            markdown += "> 📚 引用: \(citation.title) (相似度: \(citation.score))\n"
        }
        markdown += "\n"
    }

    // MARK: - Markdown → HTML 转换

    /// 将 Markdown 转换为简单 HTML（标题、段落、引用、分隔线），用于 PDF 渲染
    private static func markdownToHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var body = ""
        var pendingParagraph: [String] = []
        var pendingBlockquote: [String] = []

        func flushParagraph() {
            guard !pendingParagraph.isEmpty else { return }
            let text = pendingParagraph.joined(separator: " ")
            pendingParagraph.removeAll()
            body += "<p>\(formatInline(text))</p>\n"
        }
        func flushBlockquote() {
            guard !pendingBlockquote.isEmpty else { return }
            let inner = pendingBlockquote.map { formatInline($0) }.joined(separator: "<br>")
            pendingBlockquote.removeAll()
            body += "<blockquote>\(inner)</blockquote>\n"
        }

        for line in lines {
            if line.isEmpty {
                flushParagraph()
                flushBlockquote()
            } else if line.hasPrefix("# ") {
                flushParagraph(); flushBlockquote()
                body += "<h1>\(formatInline(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("## ") {
                flushParagraph(); flushBlockquote()
                body += "<h2>\(formatInline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("### ") {
                flushParagraph(); flushBlockquote()
                body += "<h3>\(formatInline(String(line.dropFirst(4))))</h3>\n"
            } else if line == "---" {
                flushParagraph(); flushBlockquote()
                body += "<hr>\n"
            } else if line.hasPrefix("> ") {
                flushParagraph()
                pendingBlockquote.append(String(line.dropFirst(2)))
            } else if line == ">" {
                flushParagraph()
                pendingBlockquote.append("")
            } else {
                flushBlockquote()
                pendingParagraph.append(line)
            }
        }
        flushParagraph()
        flushBlockquote()

        return """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif; font-size: 14px; line-height: 1.6; color: #1a1a1a; }
        h1 { font-size: 22px; border-bottom: 1px solid #ddd; padding-bottom: 6px; }
        h2 { font-size: 18px; color: #333; }
        h3 { font-size: 16px; color: #444; margin-top: 18px; }
        blockquote { border-left: 3px solid #4a90d9; margin: 8px 0; padding: 6px 12px; background: #f5f7fa; color: #333; }
        hr { border: none; border-top: 1px solid #ddd; margin: 16px 0; }
        p { margin: 8px 0; }
        </style></head><body>\(body)</body></html>
        """
    }

    /// 转义 HTML 特殊字符（& < >）
    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 行内格式：先转义 HTML，再将 `**xxx**` 转为 `<b>xxx</b>`
    private static func formatInline(_ text: String) -> String {
        let escaped = escapeHTML(text)
        var result = ""
        var inBold = false
        var index = escaped.startIndex
        while index < escaped.endIndex {
            let next = escaped.index(after: index)
            if next < escaped.endIndex, escaped[index] == "*", escaped[next] == "*" {
                result += inBold ? "</b>" : "<b>"
                inBold.toggle()
                index = escaped.index(index, offsetBy: 2)
            } else {
                result.append(escaped[index])
                index = next
            }
        }
        return result
    }

    // MARK: - PDF 渲染（跨平台）

    #if os(iOS)
    /// iOS PDF 页面渲染器，自定义纸张与可打印区域
    private final class ExportPageRenderer: UIPrintPageRenderer {
        private let customPaperRect: CGRect
        private let customPrintableRect: CGRect
        init(pageRect: CGRect, printableRect: CGRect) {
            self.customPaperRect = pageRect
            self.customPrintableRect = printableRect
            super.init()
        }
        override var paperRect: CGRect { customPaperRect }
        override var printableRect: CGRect { customPrintableRect }
    }

    /// iOS：使用 UIMarkupTextPrintFormatter 渲染 HTML，UIGraphicsPDFRenderer 生成 PDF Data
    private static func renderPdfIOS(html: String) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4
        let printableRect = pageRect.insetBy(dx: 36, dy: 36)
        let renderer = ExportPageRenderer(pageRect: pageRect, printableRect: printableRect)
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect, format: UIGraphicsPDFRendererFormat())
        return pdfRenderer.pdfData { context in
            for pageIndex in 0..<renderer.numberOfPages {
                context.beginPage()
                renderer.drawPage(at: pageIndex, in: context.pdfContextBounds)
            }
        }
    }
    #else
    /// macOS：使用 NSAttributedString(html:) 解析 HTML，NSPrintOperation 输出到临时 PDF 文件
    private static func renderPdfMacOS(html: String) -> Data? {
        guard let htmlData = html.data(using: .utf8) else { return nil }
        guard let attributed = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else { return nil }

        let textView = NSTextView()
        textView.textStorage?.setAttributedString(attributed)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.size = NSSize(width: 523.28, height: 100000)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aether_export_\(UUID().uuidString).pdf")

        let printOptions: [NSPrintInfo.AttributeKey: Any] = [
            .jobDisposition: NSPrintInfo.JobDisposition.save,
            .jobSavingURL: tempURL
        ]
        let printInfo = NSPrintInfo(dictionary: printOptions)
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89) // A4
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36

        let printOp = NSPrintOperation(view: textView, printInfo: printInfo)
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false
        printOp.run()

        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try? Data(contentsOf: tempURL)
    }
    #endif
}
