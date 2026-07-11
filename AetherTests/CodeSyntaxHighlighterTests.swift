import XCTest
import SwiftUI
@testable import Aether

/// CodeSyntaxHighlighter 单元测试：验证语法高亮 token 解析、主题切换、属性字符串生成与边界情况。
final class CodeSyntaxHighlighterTests: XCTestCase {

    // MARK: - Helpers

    /// 检查 AttributedString 中是否存在指定前景色的 run。
    private func containsColor(_ color: Color, in attributed: AttributedString) -> Bool {
        attributed.runs.contains { $0.attributes.foregroundColor == color }
    }

    /// 返回 AttributedString 中所有非 nil 前景色的数量。
    private func runCount(_ attributed: AttributedString) -> Int {
        attributed.runs.reduce(0) { $0 + ($1.attributes.foregroundColor != nil ? 1 : 0) }
    }

    // MARK: - SyntaxTheme

    func testThemeColorsDifferBetweenLightAndDark() {
        XCTAssertNotEqual(SyntaxTheme.light.keyword, SyntaxTheme.dark.keyword)
        XCTAssertNotEqual(SyntaxTheme.light.string, SyntaxTheme.dark.string)
        XCTAssertNotEqual(SyntaxTheme.light.comment, SyntaxTheme.dark.comment)
        XCTAssertNotEqual(SyntaxTheme.light.number, SyntaxTheme.dark.number)
        XCTAssertNotEqual(SyntaxTheme.light.type, SyntaxTheme.dark.type)
        XCTAssertNotEqual(SyntaxTheme.light.function, SyntaxTheme.dark.function)
    }

    func testThemeReturnsConsistentColors() {
        // 同一主题多次访问应返回相同颜色（RGB 一致）
        XCTAssertEqual(SyntaxTheme.dark.keyword, SyntaxTheme.dark.keyword)
        XCTAssertEqual(SyntaxTheme.light.number, SyntaxTheme.light.number)
    }

    // MARK: - 基本高亮

    func testHighlightReturnsCorrectCharacters() {
        let code = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .dark)
        XCTAssertEqual(String(result.characters), code)
    }

    func testHighlightEmptyString() {
        let result = CodeSyntaxHighlighter.highlight("", language: "swift", theme: .dark)
        XCTAssertEqual(String(result.characters), "")
    }

    func testHighlightWithNilLanguage() {
        let code = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(code, language: nil, theme: .dark)
        XCTAssertEqual(String(result.characters), code)
        // nil 语言走 allKeywords 分支，仍应高亮通用关键字和数字
        XCTAssertTrue(runCount(result) > 1, "nil 语言仍应应用高亮")
    }

    // MARK: - 关键字高亮（多语言）

    func testSwiftKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("func test() {}", language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "Swift 关键字 'func' 应被高亮")
    }

    func testPythonKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("def hello():", language: "python", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "Python 关键字 'def' 应被高亮")
    }

    func testJavaScriptKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("const x = 1;", language: "javascript", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "JavaScript 关键字 'const' 应被高亮")
    }

    func testJSONKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("{\"key\": true}", language: "json", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "JSON 关键字 'true' 应被高亮")
    }

    func testGoKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("func main() {}", language: "go", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "Go 关键字 'func' 应被高亮")
    }

    func testRustKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("fn main() {}", language: "rust", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "Rust 关键字 'fn' 应被高亮")
    }

    func testJavaKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("public class A {}", language: "java", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "Java 关键字应被高亮")
    }

    func testKotlinKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("fun main() {}", language: "kotlin", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "Kotlin 关键字 'fun' 应被高亮")
    }

    func testCKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("int main() {}", language: "c", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "C 关键字 'int' 应被高亮")
    }

    func testCppKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("int main() {}", language: "cpp", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "C++ 关键字 'int' 应被高亮")
    }

    func testSQLKeywordHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("SELECT * FROM users", language: "sql", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "SQL 关键字 'SELECT' 应被高亮")
    }

    func testSQLKeywordCaseInsensitive() {
        let lowerResult = CodeSyntaxHighlighter.highlight("select * from users", language: "sql", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: lowerResult), "SQL 关键字小写也应被高亮（大小写不敏感）")
    }

    // MARK: - 字符串高亮

    func testDoubleQuoteStringHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("let s = \"hello\"", language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.string, in: result), "双引号字符串应被高亮")
    }

    func testSingleQuoteStringHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("s = 'hello'", language: "python", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.string, in: result), "单引号字符串应被高亮")
    }

    func testStringWithEscapeSequence() {
        let result = CodeSyntaxHighlighter.highlight("s = \"he\\\"llo\"", language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.string, in: result), "含转义字符的字符串应被高亮")
    }

    // MARK: - 注释高亮

    func testSingleLineCommentHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("let x = 1 // comment", language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.comment, in: result), "单行注释 // 应被高亮")
    }

    func testHashCommentHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("x = 1 # comment", language: "python", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.comment, in: result), "# 注释应被高亮")
    }

    func testMultiLineCommentHighlighting() {
        let code = "let x = 1 /* multi\nline */ let y = 2"
        let result = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.comment, in: result), "多行注释应被高亮")
    }

    // MARK: - 数字高亮

    func testIntegerHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("let x = 42", language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.number, in: result), "整数应被高亮")
    }

    func testDecimalNumberHighlighting() {
        let result = CodeSyntaxHighlighter.highlight("let pi = 3.14", language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.number, in: result), "浮点数应被高亮")
    }

    // MARK: - 主题切换

    func testDarkThemeAppliesDarkColors() {
        let result = CodeSyntaxHighlighter.highlight("let x = 42", language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.number, in: result), "暗色主题应使用暗色 number 颜色")
        XCTAssertFalse(containsColor(SyntaxTheme.light.number, in: result), "暗色主题不应使用亮色 number 颜色")
    }

    func testLightThemeAppliesLightColors() {
        let result = CodeSyntaxHighlighter.highlight("let x = 42", language: "swift", theme: .light)
        XCTAssertTrue(containsColor(SyntaxTheme.light.number, in: result), "亮色主题应使用亮色 number 颜色")
        XCTAssertFalse(containsColor(SyntaxTheme.dark.number, in: result), "亮色主题不应使用暗色 number 颜色")
    }

    func testSameCodeDifferentThemesProduceDifferentColors() {
        let code = "let x = 42"
        let darkResult = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .dark)
        let lightResult = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .light)
        // 两个主题对 number 使用不同 RGB，应产生不同的颜色集合
        XCTAssertTrue(containsColor(SyntaxTheme.dark.number, in: darkResult))
        XCTAssertTrue(containsColor(SyntaxTheme.light.number, in: lightResult))
        XCTAssertNotEqual(SyntaxTheme.dark.number, SyntaxTheme.light.number)
    }

    // MARK: - 边界情况

    func testUnknownLanguageUsesAllKeywords() {
        let result = CodeSyntaxHighlighter.highlight("return 42", language: "unknown_lang", theme: .dark)
        XCTAssertEqual(String(result.characters), "return 42")
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "未知语言仍应高亮通用关键字")
    }

    func testLanguageCaseInsensitive() {
        let code = "let x = 42"
        let resultUpper = CodeSyntaxHighlighter.highlight(code, language: "SWIFT", theme: .dark)
        let resultMixed = CodeSyntaxHighlighter.highlight(code, language: "Swift", theme: .dark)
        XCTAssertEqual(String(resultUpper.characters), code)
        XCTAssertEqual(String(resultMixed.characters), code)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: resultUpper), "大写语言名应被识别")
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: resultMixed), "混合大小写语言名应被识别")
    }

    func testLongCodeDoesNotCrash() {
        var code = ""
        for i in 0..<500 {
            code += "let x\(i) = \(i)\n"
        }
        let result = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .dark)
        XCTAssertEqual(String(result.characters).count, code.count)
        XCTAssertTrue(runCount(result) > 1, "长代码应仍有高亮")
    }

    func testHighlightDoesNotModifyInput() {
        let code = "let x = 42"
        _ = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .dark)
        XCTAssertEqual(code, "let x = 42", "输入字符串不应被修改")
    }

    func testPlainCodeWithoutSyntaxElements() {
        let code = "   "
        let result = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .dark)
        XCTAssertEqual(String(result.characters), code)
        // 只有空格的代码不应有 keyword/string/comment/number 颜色
        XCTAssertFalse(containsColor(SyntaxTheme.dark.keyword, in: result))
        XCTAssertFalse(containsColor(SyntaxTheme.dark.string, in: result))
        XCTAssertFalse(containsColor(SyntaxTheme.dark.number, in: result))
    }

    func testMultipleHighlightTypesInOneSnippet() {
        let code = "func test() { let s = \"hello\"; let n = 42 // comment }"
        let result = CodeSyntaxHighlighter.highlight(code, language: "swift", theme: .dark)
        XCTAssertTrue(containsColor(SyntaxTheme.dark.keyword, in: result), "应包含关键字高亮")
        XCTAssertTrue(containsColor(SyntaxTheme.dark.string, in: result), "应包含字符串高亮")
        XCTAssertTrue(containsColor(SyntaxTheme.dark.number, in: result), "应包含数字高亮")
        XCTAssertTrue(containsColor(SyntaxTheme.dark.comment, in: result), "应包含注释高亮")
    }
}
