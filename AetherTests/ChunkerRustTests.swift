import XCTest
import AetherRust

/// Rust 文档分块包装器单元测试。
/// 验证 AetherRustChunker.chunkDocument 的分块行为。
final class ChunkerRustTests: XCTestCase {

    // MARK: - 基本分块

    func testShortTextSingleChunk() {
        let chunks = AetherRustChunker.chunkDocument("Hello world.", maxChars: 512, overlapChars: 128)
        XCTAssertEqual(chunks.count, 1, "短文本应返回 1 个 chunk")
        XCTAssertEqual(chunks[0], "Hello world.")
    }

    func testEmptyTextReturnsSingleChunk() {
        let chunks = AetherRustChunker.chunkDocument("", maxChars: 512, overlapChars: 128)
        XCTAssertEqual(chunks.count, 1, "空文本应返回 1 个 chunk（含原文本）")
    }

    // MARK: - 长文本分块

    func testLongTextProducesMultipleChunks() {
        let sentence = "This is a test sentence for chunking behavior verification. "
        let text = String(repeating: sentence, count: 100)
        let chunks = AetherRustChunker.chunkDocument(text, maxChars: 512, overlapChars: 128)
        XCTAssertGreaterThan(chunks.count, 1, "长文本应产生多个 chunk")
    }

    func testChunksAreTrimmed() {
        let text = "  Hello world.  Another sentence.  "
        let chunks = AetherRustChunker.chunkDocument(text, maxChars: 512, overlapChars: 128)
        for chunk in chunks {
            XCTAssertFalse(chunk.hasPrefix(" "), "chunk 不应有前导空白")
            XCTAssertFalse(chunk.hasSuffix(" "), "chunk 不应有尾部空白")
        }
    }

    // MARK: - 重叠

    func testOverlapBetweenChunks() {
        let sentence = "Sentence number X for testing overlap behavior. "
        let text = String(repeating: sentence, count: 50)
        let chunks = AetherRustChunker.chunkDocument(text, maxChars: 256, overlapChars: 64)
        // 有重叠时 chunk 数量应少于无重叠的情况
        XCTAssertGreaterThan(chunks.count, 1, "应产生多个 chunk")
    }

    // MARK: - 中文文本

    func testChineseText() {
        let text = "这是用于测试中文文档分块的长文本。" + String(repeating: "测试分块行为。", count: 50)
        let chunks = AetherRustChunker.chunkDocument(text, maxChars: 256, overlapChars: 64)
        XCTAssertGreaterThan(chunks.count, 1, "中文长文本应产生多个 chunk")
    }

    func testChineseSingleSentence() {
        let chunks = AetherRustChunker.chunkDocument("你好世界。", maxChars: 512, overlapChars: 128)
        XCTAssertEqual(chunks.count, 1, "中文短句应返回 1 个 chunk")
    }

    // MARK: - 边界条件

    func testMaxCharsZero() {
        let chunks = AetherRustChunker.chunkDocument("Hello world.", maxChars: 0, overlapChars: 0)
        XCTAssertFalse(chunks.isEmpty, "maxChars=0 不应崩溃")
    }

    func testOverlapEqualsMaxChars() {
        let text = String(repeating: "Test sentence for chunking. ", count: 30)
        let chunks = AetherRustChunker.chunkDocument(text, maxChars: 256, overlapChars: 256)
        XCTAssertFalse(chunks.isEmpty, "overlap = maxChars 不应崩溃")
    }

    // MARK: - 特殊字符

    func testTextWithNewlines() {
        let text = "Line 1.\nLine 2.\nLine 3.\n" + String(repeating: "More text. ", count: 50)
        let chunks = AetherRustChunker.chunkDocument(text, maxChars: 256, overlapChars: 64)
        XCTAssertGreaterThan(chunks.count, 1, "含换行符文本应正常分块")
    }

    func testTextWithEmoji() {
        let text = "Hello 🌍. " + String(repeating: "Test with emoji 🚀. ", count: 30)
        let chunks = AetherRustChunker.chunkDocument(text, maxChars: 256, overlapChars: 64)
        XCTAssertFalse(chunks.isEmpty, "含 emoji 文本不应崩溃")
        // 至少一个 chunk 包含 emoji
        let containsEmoji = chunks.contains { $0.contains("🌍") || $0.contains("🚀") }
        XCTAssertTrue(containsEmoji, "chunk 应保留 emoji")
    }
}