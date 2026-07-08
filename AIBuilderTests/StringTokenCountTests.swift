import XCTest
@testable import AIBuilder

/// String.estimatedTokens 表驱动单元测试
///
/// 源码实现：`Int(Double(split(separator: " ").count) * 1.3)`
/// - 按单空格 split，连续空格折叠（split 默认 omitEmptySubsequences=true）
/// - 中文无空格，整体算 1 个 token 词
/// - 最终乘以 1.3 后向零取整（Int 截断）
final class StringTokenCountTests: XCTestCase {
    func testEstimatedTokens() {
        // (输入, 期望 token 数)
        let cases: [(String, Int)] = [
            ("", 0),                       // 空字符串 split 为 0 个 → 0
            ("hello", 1),                  // 1 词 → Int(1.3) = 1
            ("hello world", 2),            // 2 词 → Int(2.6) = 2
            ("hello  world", 2),           // 连续空格 split 折叠 → 2 词
            ("你好世界", 1),                // 无空格整体算 1 词 → Int(1.3) = 1
            ("hello world foo bar", 5),    // 4 词 → Int(4 * 1.3 = 5.2) = 5
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
