import XCTest
import AetherRust

/// Rust Token 估算包装器单元测试。
/// 验证 AetherRustToken.estimateTokens 的行为。
final class TokenRustTests: XCTestCase {

    // MARK: - 基本估算

    func testEmptyStringReturnsZero() {
        let tokens = AetherRustToken.estimateTokens("")
        XCTAssertEqual(tokens, 0, "空字符串应返回 0 token")
    }

    func testSingleWord() {
        let tokens = AetherRustToken.estimateTokens("hello")
        XCTAssertGreaterThan(tokens, 0, "单个单词应返回正数 token")
    }

    func testShortSentence() {
        let tokens = AetherRustToken.estimateTokens("Hello, how are you?")
        XCTAssertGreaterThanOrEqual(tokens, 3, "短句应估算至少 3 token")
    }

    // MARK: - 确定性

    func testEstimateIsDeterministic() {
        let text = "The quick brown fox jumps over the lazy dog."
        let t1 = AetherRustToken.estimateTokens(text)
        let t2 = AetherRustToken.estimateTokens(text)
        XCTAssertEqual(t1, t2, "相同输入应产生相同估算")
    }

    // MARK: - 中文文本

    func testChineseText() {
        let tokens = AetherRustToken.estimateTokens("你好世界")
        XCTAssertGreaterThan(tokens, 0, "中文文本应返回正数 token")
    }

    func testMixedText() {
        let tokens = AetherRustToken.estimateTokens("Hello 世界 123")
        XCTAssertGreaterThan(tokens, 0, "混合文本应返回正数 token")
    }

    // MARK: - 长文本

    func testLongText() {
        let text = String(repeating: "word ", count: 1000)
        let tokens = AetherRustToken.estimateTokens(text)
        XCTAssertGreaterThan(tokens, 500, "长文本应估算较多 token")
    }

    func testTokenCountIncreasesWithTextLength() {
        let short = AetherRustToken.estimateTokens("a")
        let long = AetherRustToken.estimateTokens("a b c d e f g h i j")
        XCTAssertGreaterThan(long, short, "更长文本应估算更多 token")
    }

    // MARK: - 特殊字符

    func testSpecialCharacters() {
        let tokens = AetherRustToken.estimateTokens("!@#$%^&*()")
        XCTAssertGreaterThanOrEqual(tokens, 0, "特殊字符不应崩溃")
    }

    func testEmojiText() {
        let tokens = AetherRustToken.estimateTokens("Hello 🌍 🚀")
        XCTAssertGreaterThan(tokens, 0, "含 emoji 文本应返回正数 token")
    }
}