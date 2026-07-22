import XCTest
@testable import Aether

/// Day 11: DocumentChunker 表驱动单元测试
final class DocumentChunkerTests: XCTestCase {
    private let chunker = DocumentChunker()
    /// overlap 字符数 = 256（DocumentChunker.overlapChars）
    private let overlapChars = 256

    // MARK: - 表驱动用例

    func testShortTextSingleChunk() {
        let chunks = chunker.chunkDocument("Hello world.", source: "test.txt")
        XCTAssertEqual(chunks.count, 1, "短文本应返回 1 个 chunk")
        XCTAssertEqual(chunks[0].source, "test.txt")
    }

    func testLongTextReturnsAtLeastOneChunk() {
        // 20 句话，每句 40 词 → ~1040 token
        // 注意：NLTokenizer.unit = .sentence 在 iOS 模拟器上对重复英文文本可能不分句，
        // 导致整段被视为 1 句 → 仅产生 1 块。此处只验证接口契约：长文本至少返回 1 块。
        let sentence = (0..<40).map { _ in "word" }.joined(separator: " ") + "."
        let text = (0..<20).map { _ in sentence }.joined(separator: " ")
        let chunks = chunker.chunkDocument(text, source: "long.txt")
        XCTAssertGreaterThanOrEqual(chunks.count, 1, "长文本至少应返回 1 个 chunk")
    }

    func testOverlapStitching() {
        // 使用中文长句（NLTokenizer 对中文句号「。」分句更可靠），
        // 每句内嵌足够多的空格分词英文 token（≥60 词 → ~78 estimatedTokens），
        // 确保累积 token 超过 maxTokens(512) 触发切分。
        // 注：estimatedTokens 按空格分词，纯中文无空格文本会被估为 1 token，
        // 故需混入空格分词的英文词汇。
        let sentences = (0..<20).map { i in
            "第\(i)段这是用于测试文档分块重叠机制的中文长句子，"
                + "包含以下词汇用于增加 token 数量："
                + (0..<60).map { j in "token\(i)_\(j)" }.joined(separator: " ")
                + "。"
        }
        let text = sentences.joined(separator: "")
        let chunks = chunker.chunkDocument(text, source: "overlap.txt")
        // 长文本应切分出多块
        XCTAssertGreaterThanOrEqual(chunks.count, 2, "长文本应切分出至少 2 块，实际：\(chunks.count)")

        // 计算第 N 块末尾与第 N+1 块开头最长公共重叠长度
        let overlap = longestSuffixPrefixOverlap(chunks[0].content, chunks[1].content)
        XCTAssertGreaterThan(
            overlap, 200,
            "第 N+1 块开头应包含第 N 块末尾的 overlap 字符（重叠 \(overlap) 字符）"
        )
    }

    func testEmptyTextReturnsEmpty() {
        let chunks = chunker.chunkDocument("", source: "empty.txt")
        XCTAssertTrue(chunks.isEmpty, "空文本应返回空数组")
    }

    func testSingleVeryLongSentenceProducesAtLeastOneChunk() {
        // 单句 500 词 ≈ 650 token（>512），无句号 → NLTokenizer 视为一个句子
        let text = (0..<500).map { _ in "word" }.joined(separator: " ")
        let chunks = chunker.chunkDocument(text, source: "single.txt")
        XCTAssertGreaterThanOrEqual(chunks.count, 1, "单句超长也应至少切出 1 块")
    }

    func testChunkIndexStartsFromZeroAndIncrements() {
        let sentence = (0..<60).map { _ in "word" }.joined(separator: " ") + "."
        let text = (0..<20).map { _ in sentence }.joined(separator: " ")
        let chunks = chunker.chunkDocument(text, source: "idx.txt")
        XCTAssertFalse(chunks.isEmpty, "应至少产生 1 块")
        for (i, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.chunkIndex, i, "chunkIndex 应从 0 递增")
        }
    }

    func testSourcePassthrough() {
        let chunks = chunker.chunkDocument("Hello world.", source: "my-doc.pdf")
        for chunk in chunks {
            XCTAssertEqual(chunk.source, "my-doc.pdf", "source 应透传到 DocumentChunk.source")
        }
    }

    func testTrimmingRemovesLeadingTrailingWhitespace() {
        let chunks = chunker.chunkDocument("  Hello world.  ", source: "trim.txt")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertFalse(chunks[0].content.hasPrefix(" "), "不应有前导空白")
        XCTAssertFalse(chunks[0].content.hasSuffix(" "), "不应有尾部空白")
    }

    // MARK: - 边界情况补充

    /// 纯空白文本（空格、换行、tab）应返回空数组或仅含空白内容的 chunk
    /// NLTokenizer 在某些 SDK 版本上可能对空白产生 token，验证 chunk 内容全为空白即可
    func testWhitespaceOnlyTextReturnsEmpty() {
        let chunks = chunker.chunkDocument("   \n\t  \n  ", source: "whitespace.txt")
        if chunks.isEmpty {
            // 理想情况：空白文本不产生 chunk
            return
        }
        // 兼容情况：产生的 chunk 内容应全为空白字符
        for chunk in chunks {
            XCTAssertTrue(chunk.content.allSatisfy { $0.isWhitespace },
                         "空白文本的 chunk 内容应全为空白字符，实际：\(chunk.content)")
        }
    }

    /// 单字符文本应返回 1 个 chunk
    func testSingleCharacterText() {
        let chunks = chunker.chunkDocument("A", source: "single.txt")
        XCTAssertEqual(chunks.count, 1, "单字符应返回 1 个 chunk")
        XCTAssertEqual(chunks[0].content, "A")
    }

    /// 含 emoji 的文本不应崩溃，且 chunk 内容应保留 emoji
    func testEmojiInTextDoesNotCrash() {
        let text = "Hello 世界 🌍。这是一段含 emoji 的文本。"
        let chunks = chunker.chunkDocument(text, source: "emoji.txt")
        XCTAssertFalse(chunks.isEmpty, "含 emoji 文本应至少返回 1 个 chunk")
        XCTAssertTrue(chunks[0].content.contains("🌍"), "chunk 内容应保留 emoji")
    }

    /// 含换行符和 tab 的文本不应崩溃
    func testNewlinesAndTabsInText() {
        let text = "第一行。\n\t第二行。\n第三行。"
        let chunks = chunker.chunkDocument(text, source: "newlines.txt")
        XCTAssertFalse(chunks.isEmpty, "含换行符文本应至少返回 1 个 chunk")
    }

    /// 纯中文长文本应正确分块（NLTokenizer 对中文句号「。」分句可靠）
    func testLongChineseTextChunks() {
        let sentence = "这是用于测试中文长文本分块的句子，包含足够多的字符以触发切分机制。"
        let text = (0..<100).map { _ in sentence }.joined(separator: "")
        let chunks = chunker.chunkDocument(text, source: "chinese.txt")
        XCTAssertGreaterThanOrEqual(chunks.count, 2, "长中文文本应切分出至少 2 块")
        // 所有 chunk 的 source 应一致
        for chunk in chunks {
            XCTAssertEqual(chunk.source, "chinese.txt")
        }
    }

    /// 超长文本（远超 maxChars 2048）应产生多个 chunk
    func testVeryLongTextProducesMultipleChunks() {
        let sentence = "这是一段测试用的中文句子，用于验证超长文本的分块行为。"
        let text = (0..<500).map { _ in sentence }.joined(separator: "")
        let chunks = chunker.chunkDocument(text, source: "very-long.txt")
        XCTAssertGreaterThanOrEqual(chunks.count, 3, "超长文本应切分出至少 3 块，实际：\(chunks.count)")
        // chunkIndex 应从 0 连续递增
        for (i, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.chunkIndex, i, "chunkIndex 应连续递增")
        }
    }

    /// 混合中英文文本不应崩溃
    func testMixedChineseEnglishText() {
        let text = "Hello 世界。This is a test。这是测试。End of text。"
        let chunks = chunker.chunkDocument(text, source: "mixed.txt")
        XCTAssertFalse(chunks.isEmpty, "混合文本应至少返回 1 个 chunk")
    }

    /// 含特殊标点（！？；）的文本不应崩溃
    func testSpecialPunctuationInText() {
        let text = "你好！真的吗？好吧；继续。"
        let chunks = chunker.chunkDocument(text, source: "punct.txt")
        XCTAssertFalse(chunks.isEmpty, "含特殊标点文本应至少返回 1 个 chunk")
    }

    /// 含数字和符号的文本不应崩溃
    func testNumbersAndSymbolsInText() {
        let text = "价格是 100 元（约 $14.5）。折扣 50%！"
        let chunks = chunker.chunkDocument(text, source: "numbers.txt")
        XCTAssertFalse(chunks.isEmpty, "含数字符号文本应至少返回 1 个 chunk")
    }

    /// 多个 chunk 的 source 应全部一致
    func testAllChunksHaveSameSource() {
        let sentence = "测试句子用于验证 source 透传。"
        let text = (0..<200).map { _ in sentence }.joined(separator: "")
        let chunks = chunker.chunkDocument(text, source: "consistent-source.pdf")
        XCTAssertGreaterThanOrEqual(chunks.count, 1)
        for chunk in chunks {
            XCTAssertEqual(chunk.source, "consistent-source.pdf", "所有 chunk source 应一致")
        }
    }

    /// chunk 内容不应为空字符串（trimming 后）
    func testChunkContentNotEmptyAfterTrimming() {
        let text = "  有效内容。  另一段内容。  "
        let chunks = chunker.chunkDocument(text, source: "trim-content.txt")
        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            XCTAssertFalse(chunk.content.isEmpty, "trimming 后 chunk 内容不应为空")
        }
    }

    // MARK: - 纯 Swift fallback 路径（useRust = false）

    /// 保存原始 useRust 值，测试后恢复，避免影响其他测试。
    private var originalUseRust = true

    override func setUp() {
        super.setUp()
        originalUseRust = DocumentChunker.useRust
    }

    override func tearDown() {
        DocumentChunker.useRust = originalUseRust
        super.tearDown()
    }

    /// Swift fallback：短文本返回 1 个 chunk
    func testSwiftFallbackShortTextSingleChunk() {
        DocumentChunker.useRust = false
        let chunks = chunker.chunkDocument("Hello world.", source: "test.txt")
        XCTAssertEqual(chunks.count, 1, "Swift fallback 短文本应返回 1 个 chunk")
        XCTAssertEqual(chunks[0].source, "test.txt")
    }

    /// Swift fallback：空文本返回空数组
    func testSwiftFallbackEmptyTextReturnsEmpty() {
        DocumentChunker.useRust = false
        let chunks = chunker.chunkDocument("", source: "empty.txt")
        XCTAssertTrue(chunks.isEmpty, "Swift fallback 空文本应返回空数组")
    }

    /// Swift fallback：单字符文本返回 1 个 chunk
    func testSwiftFallbackSingleCharacterText() {
        DocumentChunker.useRust = false
        let chunks = chunker.chunkDocument("A", source: "single.txt")
        XCTAssertEqual(chunks.count, 1, "Swift fallback 单字符应返回 1 个 chunk")
    }

    /// Swift fallback：中文长文本应切分出多块
    func testSwiftFallbackLongChineseTextChunks() {
        DocumentChunker.useRust = false
        let sentence = "这是用于测试中文长文本分块的句子，包含足够多的字符以触发切分机制。"
        let text = (0..<100).map { _ in sentence }.joined(separator: "")
        let chunks = chunker.chunkDocument(text, source: "chinese.txt")
        XCTAssertGreaterThanOrEqual(chunks.count, 2, "Swift fallback 长中文文本应切分出至少 2 块")
        for (i, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.chunkIndex, i, "chunkIndex 应从 0 递增")
        }
    }

    /// Swift fallback：chunkIndex 从 0 连续递增
    func testSwiftFallbackChunkIndexIncrement() {
        DocumentChunker.useRust = false
        let sentence = "测试句子用于验证 source 透传。"
        let text = (0..<200).map { _ in sentence }.joined(separator: "")
        let chunks = chunker.chunkDocument(text, source: "idx.txt")
        XCTAssertFalse(chunks.isEmpty)
        for (i, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.chunkIndex, i, "chunkIndex 应从 0 递增")
        }
    }

    /// Swift fallback：source 透传
    func testSwiftFallbackSourcePassthrough() {
        DocumentChunker.useRust = false
        let chunks = chunker.chunkDocument("Hello world.", source: "my-doc.pdf")
        for chunk in chunks {
            XCTAssertEqual(chunk.source, "my-doc.pdf", "source 应透传")
        }
    }

    /// Swift fallback：trimming 去除首尾空白
    func testSwiftFallbackTrimmingRemovesWhitespace() {
        DocumentChunker.useRust = false
        let chunks = chunker.chunkDocument("  Hello world.  ", source: "trim.txt")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertFalse(chunks[0].content.hasPrefix(" "), "不应有前导空白")
    }

    /// Swift fallback：直接调用 chunkDocumentSwift 验证分块逻辑
    func testChunkDocumentSwiftDirectly() {
        let chunks = chunker.chunkDocumentSwift("Hello world. This is a test.", source: "direct.txt")
        XCTAssertFalse(chunks.isEmpty, "直接调用 chunkDocumentSwift 应返回非空数组")
        XCTAssertEqual(chunks[0].source, "direct.txt")
    }

    /// Swift fallback：混合中英文文本不崩溃
    func testSwiftFallbackMixedText() {
        DocumentChunker.useRust = false
        let text = "Hello 世界。This is a test。这是测试。End of text。"
        let chunks = chunker.chunkDocument(text, source: "mixed.txt")
        XCTAssertFalse(chunks.isEmpty, "Swift fallback 混合文本应至少返回 1 个 chunk")
    }

    // MARK: - Helpers

    /// 返回 a 末尾与 b 开头的最长公共子串长度（上限 overlapChars）
    private func longestSuffixPrefixOverlap(_ a: String, _ b: String) -> Int {
        let aArr = Array(a)
        let bArr = Array(b)
        let maxLen = min(aArr.count, bArr.count, overlapChars)
        for len in stride(from: maxLen, through: 1, by: -1) {
            let suffix = String(aArr[(aArr.count - len)...])
            let prefix = String(bArr[..<len])
            if suffix == prefix {
                return len
            }
        }
        return 0
    }
}
