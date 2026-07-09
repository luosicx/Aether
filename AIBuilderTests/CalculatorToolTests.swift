import XCTest
@testable import Aether

/// Day 11: CalculatorTool 表驱动单元测试
final class CalculatorToolTests: XCTestCase {
    private let tool = CalculatorTool()

    /// 表驱动测试用例：(表达式, 期望结果)
    private let cases: [(expression: String, expected: String)] = [
        ("1 + 2", "3"),
        ("10 - 4", "6"),
        ("3 * 4", "12"),
        ("15 / 4", "3.75"),
        ("1 + 2 * 3", "7"),                    // 乘法优先
        ("(1 + 2) * 3", "9"),                   // 括号
        ("3.14 * 2", "6.28"),                   // 浮点
        ("2 * (3 + 4) - 1", "13"),              // 复合
        ("1 / 0", "错误：除零"),                 // 除零
        ("1 + ", "错误：表达式无效"),            // 无效表达式
        ("abc", "错误：表达式无效"),             // 非法字符
        ("", "错误：请提供表达式")              // 空表达式
    ]

    func testCalculatorExpressions() async throws {
        for (expr, expected) in cases {
            let result = try await tool.execute(arguments: ["expression": expr])
            XCTAssertEqual(result, expected, "表达式「\(expr)」期望「\(expected)」实际「\(result)」")
        }
    }
}
