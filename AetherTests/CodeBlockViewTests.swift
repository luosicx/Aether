import XCTest
import SwiftUI
@testable import Aether

/// CodeBlockView 单元测试
///
/// 可测试内容：
/// - code / language 属性在初始化后被正确保留
/// - 通过访问 body 触发 highlightedText → CodeSyntaxHighlighter.highlight() 计算链路
///
/// 注意：`highlightedText` / `theme` / `background` 均为 private 计算属性，
/// 无法直接断言高亮结果（CodeSyntaxHighlighter 已在 CodeSyntaxHighlighterTests 中独立测试）。
@MainActor
final class CodeBlockViewTests: XCTestCase {

    // MARK: - View 初始化

    /// code 和 language 在初始化后被正确保留
    func testInitPreservesCodeAndLanguage() {
        let view = CodeBlockView(code: "let x = 42", language: "swift")
        XCTAssertEqual(view.code, "let x = 42")
        XCTAssertEqual(view.language, "swift")
    }

    /// language 为 nil 时可正常构造
    func testInitWithNilLanguage() {
        let view = CodeBlockView(code: "print('hi')", language: nil)
        XCTAssertEqual(view.code, "print('hi')")
        XCTAssertNil(view.language)
    }

    /// 空代码字符串可正常构造
    func testInitWithEmptyCode() {
        let view = CodeBlockView(code: "", language: "python")
        XCTAssertEqual(view.code, "")
        XCTAssertEqual(view.language, "python")
    }

    /// 空语言字符串可正常构造
    func testInitWithEmptyLanguage() {
        let view = CodeBlockView(code: "some code", language: "")
        XCTAssertEqual(view.language, "")
    }

    // MARK: - body smoke test（触发 highlightedText 高亮计算）

    /// 带语言和代码的 body 计算不崩溃
    func testBodyWithCodeAndLanguageDoesNotCrash() {
        let view = CodeBlockView(code: "let x = 42", language: "swift")
        _ = view.body
    }

    /// 空代码的 body 计算不崩溃
    func testBodyWithEmptyCodeDoesNotCrash() {
        let view = CodeBlockView(code: "", language: "swift")
        _ = view.body
    }

    /// nil 语言的 body 计算不崩溃
    func testBodyWithNilLanguageDoesNotCrash() {
        let view = CodeBlockView(code: "some code", language: nil)
        _ = view.body
    }

    /// 空语言的 body 计算不崩溃（language 为 "" 时不显示语言标签栏）
    func testBodyWithEmptyLanguageDoesNotCrash() {
        let view = CodeBlockView(code: "code", language: "")
        _ = view.body
    }

    /// 多种语言的 body 计算均不崩溃
    func testBodyWithMultipleLanguagesDoesNotCrash() {
        let languages = ["swift", "python", "javascript", "go", "rust",
                         "java", "kotlin", "c", "cpp", "sql", "json",
                         "unknown_lang", "SWIFT", "Python"]
        for lang in languages {
            let view = CodeBlockView(code: "test code 123", language: lang)
            _ = view.body
        }
    }

    /// 含多种语法元素的代码的 body 计算不崩溃
    func testBodyWithComplexCodeDoesNotCrash() {
        let code = """
        func test() {
            let s = "hello"
            let n = 42
            // comment
        }
        """
        let view = CodeBlockView(code: code, language: "swift")
        _ = view.body
    }

    /// 仅含空白字符的代码的 body 计算不崩溃
    func testBodyWithWhitespaceOnlyCodeDoesNotCrash() {
        let view = CodeBlockView(code: "   \n  \t  ", language: "swift")
        _ = view.body
    }

    /// 长代码的 body 计算不崩溃
    func testBodyWithLongCodeDoesNotCrash() {
        var code = ""
        for i in 0..<200 {
            code += "let x\(i) = \(i)\n"
        }
        let view = CodeBlockView(code: code, language: "swift")
        _ = view.body
    }
}
