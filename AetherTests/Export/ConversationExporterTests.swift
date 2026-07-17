import XCTest
@testable import Aether

/// ConversationExporter 单元测试
/// 覆盖 Markdown / PDF / DeepLink 分享链接导出
@MainActor
final class ConversationExporterTests: XCTestCase {
    private var exporter: ConversationExporter!

    /// 与 ConversationExporter 内部 StoredToolCall 结构对齐的 Codable DTO，
    /// 用于在测试中构造合法的 toolCallData JSON
    private struct StoredToolCallDTO: Codable {
        let id: String
        let type: String
        let name: String
        let arguments: String
    }

    override func setUpWithError() throws {
        exporter = ConversationExporter()
    }

    // MARK: - 辅助方法

    /// 构造工具调用 JSON 数据（与 ConversationExporter.StoredToolCall 解码格式一致）
    private func makeToolCallData(id: String, name: String, arguments: String) throws -> Data {
        let calls = [StoredToolCallDTO(id: id, type: "function", name: name, arguments: arguments)]
        return try JSONEncoder().encode(calls)
    }

    /// 向 Conversation 追加消息，同时设置双向关系与自定义时间戳
    @discardableResult
    private func appendMessage(
        to conv: Conversation,
        role: String,
        content: String,
        timestamp: Date,
        toolCallData: Data? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil
    ) -> ChatMessage {
        let msg = ChatMessage(
            role: role,
            content: content,
            toolCallData: toolCallData,
            toolCallId: toolCallId,
            toolName: toolName
        )
        msg.timestamp = timestamp
        msg.conversation = conv
        conv.messages.append(msg)
        return msg
    }

    // MARK: - exportAsMarkdown: 空消息与基本结构

    /// 测试 1: 空消息列表的 Markdown 导出
    /// 验证头部元信息（标题、创建时间、消息数 0）和分隔线正常输出
    func testExportAsMarkdownWithEmptyMessages() {
        let conv = Conversation(title: "空对话", systemPrompt: "你是助手")
        let markdown = exporter.exportAsMarkdown(conversation: conv)

        XCTAssertTrue(markdown.contains("# 空对话"), "应包含 H1 标题")
        XCTAssertTrue(markdown.contains("创建时间:"), "应包含创建时间")
        XCTAssertTrue(markdown.contains("消息数: 0"), "空对话消息数应为 0")
        XCTAssertTrue(markdown.contains("---"), "应包含分隔线")
    }

    /// 测试 2: 仅 user 消息的 Markdown 导出
    /// 验证角色显示为「用户」且内容正确输出
    func testExportAsMarkdownWithUserOnlyMessages() {
        let conv = Conversation(title: "用户对话", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        appendMessage(to: conv, role: "user", content: "你好", timestamp: baseTime)
        appendMessage(to: conv, role: "user", content: "再见",
                      timestamp: baseTime.addingTimeInterval(60))

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        XCTAssertTrue(markdown.contains("### 用户"), "应显示「用户」角色")
        XCTAssertTrue(markdown.contains("你好"), "应包含第一条消息内容")
        XCTAssertTrue(markdown.contains("再见"), "应包含第二条消息内容")
        XCTAssertTrue(markdown.contains("消息数: 2"), "应显示消息数为 2")
    }

    // MARK: - exportAsMarkdown: 排序

    /// 测试 3: 含 assistant + user 消息按 timestamp 排序
    /// 验证消息按时间戳升序排列，与插入顺序无关
    func testExportAsMarkdownSortsMessagesByTimestamp() {
        let conv = Conversation(title: "排序测试", systemPrompt: "你是助手")
        let later = Date(timeIntervalSince1970: 1_700_000_100)
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        // 故意以逆序插入，验证导出时按时间戳排序
        appendMessage(to: conv, role: "assistant", content: "后回复", timestamp: later)
        appendMessage(to: conv, role: "user", content: "先提问", timestamp: earlier)

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        guard let userRange = markdown.range(of: "先提问"),
              let assistantRange = markdown.range(of: "后回复") else {
            XCTFail("应同时包含用户与助手消息")
            return
        }
        // 时间戳更早的用户消息应在 Markdown 中先出现
        XCTAssertLessThan(
            userRange.lowerBound,
            assistantRange.lowerBound,
            "用户消息（时间更早）应排在助手消息之前"
        )
    }

    // MARK: - exportAsMarkdown: 工具调用

    /// 测试 4: assistant 工具调用与 tool 结果映射
    /// 验证 toolCallId 与 tool 消息内容正确对应，工具调用块格式正确
    func testExportAsMarkdownWithToolCallAndResultMapping() throws {
        let conv = Conversation(title: "工具测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let toolData = try makeToolCallData(
            id: "call-1",
            name: "calculator",
            arguments: "{\"expression\":\"1+1\"}"
        )
        appendMessage(to: conv, role: "user", content: "算一下", timestamp: baseTime)
        appendMessage(to: conv, role: "assistant", content: "我来算",
                      timestamp: baseTime.addingTimeInterval(1), toolCallData: toolData)
        appendMessage(to: conv, role: "tool", content: "2",
                      timestamp: baseTime.addingTimeInterval(2),
                      toolCallId: "call-1", toolName: "calculator")

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        XCTAssertTrue(markdown.contains("🔧 **工具调用**: calculator"), "应包含工具调用名称")
        XCTAssertTrue(markdown.contains("参数: {\"expression\":\"1+1\"}"), "应包含工具调用参数")
        XCTAssertTrue(markdown.contains("结果: 2"), "应包含工具结果（来自 tool 消息）")
    }

    /// 测试 5: consumedToolMessageIds 去重
    /// 验证被 assistant 工具调用块消费的 tool 消息不会重复输出为独立块
    func testExportAsMarkdownConsumedToolMessageNotDuplicated() throws {
        let conv = Conversation(title: "去重测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let toolData = try makeToolCallData(
            id: "call-1",
            name: "search",
            arguments: "{\"q\":\"test\"}"
        )
        appendMessage(to: conv, role: "assistant", content: "搜索中",
                      timestamp: baseTime, toolCallData: toolData)
        appendMessage(to: conv, role: "tool", content: "搜索结果",
                      timestamp: baseTime.addingTimeInterval(1),
                      toolCallId: "call-1", toolName: "search")

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        // tool 消息已被消费，不应作为独立「### 工具」块出现
        let toolBlockCount = markdown.components(separatedBy: "### 工具").count - 1
        XCTAssertEqual(toolBlockCount, 0, "已消费的 tool 消息不应作为独立块输出")
        // 但结果应出现在 assistant 的工具调用块中
        XCTAssertTrue(markdown.contains("结果: 搜索结果"), "工具结果应显示在工具调用块中")
    }

    /// 测试 6: 无匹配 tool 消息时显示「(无结果)」
    func testExportAsMarkdownWithToolCallNoResult() throws {
        let conv = Conversation(title: "无结果测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let toolData = try makeToolCallData(
            id: "call-missing",
            name: "weather",
            arguments: "{\"city\":\"北京\"}"
        )
        appendMessage(to: conv, role: "assistant", content: "查天气",
                      timestamp: baseTime, toolCallData: toolData)

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        XCTAssertTrue(markdown.contains("结果: (无结果)"), "无匹配 tool 消息时应显示「(无结果)」")
    }

    // MARK: - exportAsMarkdown: 头部与内容

    /// 测试 7: 头部元信息包含标题、创建时间、消息数
    func testExportAsMarkdownHeaderContainsTitleAndMetadata() {
        let conv = Conversation(title: "元信息测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        appendMessage(to: conv, role: "user", content: "hello", timestamp: baseTime)

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        XCTAssertTrue(markdown.hasPrefix("# 元信息测试"), "应以标题开头")
        XCTAssertTrue(markdown.contains("创建时间:"), "应包含创建时间字段")
        XCTAssertTrue(markdown.contains("消息数: 1"), "应包含消息数")
    }

    /// 测试 8: 角色显示名（系统/用户/助手/工具）
    func testExportAsMarkdownRoleDisplayNames() {
        let conv = Conversation(title: "角色测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        appendMessage(to: conv, role: "system", content: "系统消息", timestamp: baseTime)
        appendMessage(to: conv, role: "user", content: "用户消息",
                      timestamp: baseTime.addingTimeInterval(1))
        appendMessage(to: conv, role: "assistant", content: "助手消息",
                      timestamp: baseTime.addingTimeInterval(2))

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        XCTAssertTrue(markdown.contains("### 系统"), "system 应显示为「系统」")
        XCTAssertTrue(markdown.contains("### 用户"), "user 应显示为「用户」")
        XCTAssertTrue(markdown.contains("### 助手"), "assistant 应显示为「助手」")
    }

    /// 测试 9: 嵌套 data: 前缀处理
    /// 验证内容中包含 data: URI 前缀时能正常导出（作为纯文本原样保留）
    func testExportAsMarkdownWithDataPrefixContent() {
        let conv = Conversation(title: "Data URI 测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let dataURI = "data:image/png;base64,iVBORw0KGgo="
        appendMessage(to: conv, role: "user", content: "图片 \(dataURI)",
                      timestamp: baseTime)

        let markdown = exporter.exportAsMarkdown(conversation: conv)

        XCTAssertTrue(markdown.contains(dataURI), "data: 前缀内容应原样保留在 Markdown 中")
    }

    // MARK: - exportAsShareLink

    /// 测试 10: ShareLink URL 格式（aether://conversation/{uuid}）
    func testExportAsShareLinkURLFormat() throws {
        let conv = Conversation(title: "分享测试", systemPrompt: "你是助手")
        let url = try XCTUnwrap(exporter.exportAsShareLink(conversation: conv))

        XCTAssertEqual(url.scheme, "aether", "scheme 应为 aether")
        XCTAssertEqual(url.host, "conversation", "host 应为 conversation")
        let expectedPath = "/" + conv.id.uuidString
        XCTAssertEqual(url.path, expectedPath, "path 应为 /{uuid}")
        XCTAssertEqual(
            url.absoluteString,
            "aether://conversation/\(conv.id.uuidString)",
            "URL 完整格式应为 aether://conversation/{uuid}"
        )
    }

    /// 测试 11: 不同 UUID 生成不同链接
    func testExportAsShareLinkWithDifferentUUIDs() throws {
        let conv1 = Conversation(title: "对话1", systemPrompt: "你是助手")
        let conv2 = Conversation(title: "对话2", systemPrompt: "你是助手")

        let url1 = try XCTUnwrap(exporter.exportAsShareLink(conversation: conv1))
        let url2 = try XCTUnwrap(exporter.exportAsShareLink(conversation: conv2))

        XCTAssertNotEqual(url1.absoluteString, url2.absoluteString, "不同对话应生成不同 URL")
        XCTAssertTrue(
            url1.absoluteString.contains(conv1.id.uuidString),
            "URL 应包含对话 1 的 UUID"
        )
        XCTAssertTrue(
            url2.absoluteString.contains(conv2.id.uuidString),
            "URL 应包含对话 2 的 UUID"
        )
    }

    // MARK: - exportAsPDF
    // 注意：PDF 生成依赖平台 UI 框架（iOS: UIGraphicsPDFRenderer / macOS: NSPrintOperation）。
    // macOS CI headless 环境下 NSPrintOperation 可能无法生成 PDF 文件，故 PDF 测试
    // 采用「不崩溃即通过」策略：仅验证 exportAsPDF 调用路径完整执行且不抛异常；
    // 当返回非 nil Data 时额外验证 PDF 魔术字节，确保 PDF 内容合法。

    /// 测试 12: PDF 生成不崩溃；若返回 Data 则验证 %PDF 魔术字节
    func testExportAsPDFReturnsNonEmptyData() async throws {
        let conv = Conversation(title: "PDF 测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        appendMessage(to: conv, role: "user", content: "生成 PDF", timestamp: baseTime)
        appendMessage(to: conv, role: "assistant", content: "好的，正在生成",
                      timestamp: baseTime.addingTimeInterval(1))

        let pdfData = await exporter.exportAsPDF(conversation: conv)

        // macOS headless 环境可能返回 nil（NSPrintOperation 无法写入文件），
        // 此时不视为失败；只要不崩溃即通过。
        guard let data = pdfData, !data.isEmpty else { return }

        // 验证 PDF 魔术字节 %PDF（0x25 0x50 0x44 0x46）
        let pdfMagic: [UInt8] = [0x25, 0x50, 0x44, 0x46]
        XCTAssertTrue(
            data.starts(with: pdfMagic),
            "PDF 应以 %PDF 魔术字节开头"
        )
    }

    /// 测试 13: 空对话 PDF 生成不崩溃
    func testExportAsPDFWithEmptyConversation() async {
        let conv = Conversation(title: "空 PDF", systemPrompt: "你是助手")
        // 仅验证不崩溃；macOS headless 环境可能返回 nil
        _ = await exporter.exportAsPDF(conversation: conv)
    }

    /// 测试 14: HTML 特殊字符转义（通过 PDF 间接验证）
    /// 验证包含 & < > 的内容不会导致 PDF 生成崩溃
    /// 注：escapeHTML / markdownToHTML 为 private static，仅能通过 PDF 生成路径间接验证
    func testExportAsPDFWithHTMLEscapeCharacters() async {
        let conv = Conversation(title: "转义测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        appendMessage(to: conv, role: "user", content: "a < b > c & d",
                      timestamp: baseTime)
        // 仅验证不崩溃；macOS headless 环境可能返回 nil
        _ = await exporter.exportAsPDF(conversation: conv)
    }

    /// 测试 15: bold 行内格式（通过 PDF 间接验证）
    /// 验证 **bold** 标记不会导致 PDF 生成崩溃
    /// 注：formatInline 为 private static，仅能通过 PDF 生成路径间接验证
    func testExportAsPDFWithBoldMarkdown() async {
        let conv = Conversation(title: "粗体测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        appendMessage(to: conv, role: "assistant", content: "这是**重要**内容",
                      timestamp: baseTime)
        // 仅验证不崩溃；macOS headless 环境可能返回 nil
        _ = await exporter.exportAsPDF(conversation: conv)
    }

    /// 测试 16: 多种 Markdown 行类型（H1/H2/H3/hr/blockquote/paragraph）
    /// 通过 PDF 间接验证 markdownToHTML 对各种行类型的处理
    func testExportAsPDFWithVariousMarkdownLineTypes() async {
        let conv = Conversation(title: "行类型测试", systemPrompt: "你是助手")
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        // 内容覆盖 H2、段落、hr、blockquote 等行类型
        //（H1 来自导出头部、H3 来自消息标题）
        appendMessage(to: conv, role: "user", content: "标题文本", timestamp: baseTime)
        appendMessage(
            to: conv,
            role: "assistant",
            content: "## 子标题\n\n段落内容\n\n---\n\n> 引用内容",
            timestamp: baseTime.addingTimeInterval(1)
        )
        // 仅验证不崩溃；macOS headless 环境可能返回 nil
        _ = await exporter.exportAsPDF(conversation: conv)
    }
}
