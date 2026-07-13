#if os(macOS)
import XCTest
@testable import Aether

final class SafariControlToolTests: XCTestCase {
    private let tool = SafariControlTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "control_safari")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteUnsupportedAction() async throws {
        let result = try await tool.execute(arguments: ["action": "unknown"])
        XCTAssertTrue(result.hasPrefix("错误"))
    }

    // MARK: - AppleScript 注入防护

    /// 验证 appleScriptEscaped 会转义双引号，防止字符串边界被突破。
    func testAppleScriptEscapingEscapesQuotes() {
        // 使用原始字符串字面量避免转义混乱；输入含未转义双引号企图跳出 AppleScript 字面量
        let input = #"http://example.com"; do shell script "rm -rf ~"; --"#
        let output = SafariControlTool.appleScriptEscaped(input)
        // 输出中所有双引号都必须被反斜杠转义（即不存在未转义的双引号）
        XCTAssertNil(output.range(of: #"(?<!\\)\""#, options: .regularExpression),
                     "存在未转义的双引号: \(output)")
    }

    /// 验证反斜杠先被转义，避免与后续转义的双引号组合成新的转义序列。
    func testAppleScriptEscapingEscapesBackslashesBeforeQuotes() {
        // 输入: http://example.com\"; do shell script "echo pwned"; --
        let input = #"http://example.com\"; do shell script "echo pwned"; --"#
        let output = SafariControlTool.appleScriptEscaped(input)
        // 期望输出前缀: http://example.com + 三个反斜杠 + 引号
        // （原反斜杠 → \\，原引号 → \"，合计 \\\"）
        XCTAssertTrue(output.hasPrefix(#"http://example.com\\\""#),
                      "反斜杠应先转义为 \\，引号再转义为 \": \(output)")
    }

    /// 验证换行、回车、制表符被转义，避免注入多行 AppleScript。
    func testAppleScriptEscapingEscapesControlCharacters() {
        let input = "line1\nline2\rline3\ttab"
        let output = SafariControlTool.appleScriptEscaped(input)
        XCTAssertFalse(output.contains("\n"))
        XCTAssertFalse(output.contains("\r"))
        XCTAssertFalse(output.contains("\t"))
        XCTAssertTrue(output.contains("\\n"))
        XCTAssertTrue(output.contains("\\r"))
        XCTAssertTrue(output.contains("\\t"))
    }

    /// 正常 URL 不应被误伤。
    func testAppleScriptEscapingPreservesNormalURL() {
        let input = "https://www.apple.com/ios/ios-18/?foo=bar&baz=qux"
        let output = SafariControlTool.appleScriptEscaped(input)
        XCTAssertEqual(output, input)
    }
}
#endif
