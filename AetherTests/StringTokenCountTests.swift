import XCTest
@testable import Aether

/// String.estimatedTokens 表驱动单元测试
///
/// 源码实现：英文按空格分词乘 1.3 + 非 ASCII 字符每字 1.5
/// - 空字符串 → 0
/// - 纯英文按空格分词
/// - 中文每字约 1.5 token
final class StringTokenCountTests: XCTestCase {
    func testEstimatedTokens() {
        // (输入, 期望 token 数)
        let cases: [(String, Int)] = [
            ("", 0),                       // 空字符串 → 0
            ("hello", 1),                  // 1 词 → Int(1.3) = 1
            ("hello world", 2),            // 2 词 → Int(2.6) = 2
            ("hello  world", 2),           // 连续空格 split 折叠 → 2 词
            ("你好世界", 7),                // 1 词 Int(1.3) + 4 非 ASCII 字 Int(4*1.5) = 1+6 = 7
            ("hello world foo bar", 5),    // 4 词 → Int(4 * 1.3 = 5.2) = 5
            ("你好 hello", 5)              // 2 英文词 Int(2*1.3) + 2 中文字 Int(2*1.5) = 2+3 = 5
        ]
        for (input, expected) in cases {
            XCTAssertEqual(
                input.estimatedTokens,
                expected,
                "input: '\(input)'"
            )
        }
    }
}
