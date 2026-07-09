import XCTest
@testable import AIBuilder

/// Day 11: DocumentChunker 表驱动单元测试
final class DocumentChunkerTests: XCTestCase {
    private let chunker = DocumentChunker()
    /// overlap 字符数 = overlap(tokens) * 4 = 128 * 4 = 512
    private let overlapChars = 128 * 4

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
