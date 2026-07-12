import XCTest
import SwiftUI
@testable import Aether

/// MarkdownText 单元测试
///
/// 注意：`parseBlocks()` / `parseTextSegment()` / `MarkdownBlock` 枚举 / `cachedBlocks` 均为 private，
/// 无法在不修改实现代码的前提下直接断言解析结果。
/// 本测试通过访问 `body` 属性触发 `cachedBlocks` → `parseBlocks()` 解析链路，
/// 验证各种 Markdown 输入不会导致解析崩溃（smoke test）。
@MainActor
final class MarkdownTextTests: XCTestCase {

    // MARK: - View 初始化

    /// 验证 content 属性在初始化后被正确保留
    func testInitPreservesContent() {
        let view = MarkdownText(content: "# Hello")
        XCTAssertEqual(view.content, "# Hello")
    }

    /// 验证空字符串可作为 content 传入
    func testInitWithEmptyContent() {
        let view = MarkdownText(content: "")
        XCTAssertEqual(view.content, "")
    }

    // MARK: - 解析 smoke test（通过访问 body 触发 parseBlocks）

    /// 空文本不应导致解析崩溃
    func testParseEmptyTextDoesNotCrash() {
        let view = MarkdownText(content: "")
        _ = view.body
    }

    /// 纯文本不应导致解析崩溃
    func testParsePlainTextDoesNotCrash() {
        let view = MarkdownText(content: "这是一段纯文本，没有 Markdown 语法。")
        _ = view.body
    }

    /// 带语言标识的代码块不应导致解析崩溃
    func testParseCodeBlockWithLanguageDoesNotCrash() {
        let content = """
        ```swift
        let x = 42
        ```
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 不带语言标识的代码块不应导致解析崩溃
    func testParseCodeBlockWithoutLanguageDoesNotCrash() {
        let content = """
        ```
        plain code
        ```
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 语言行包含空格时不应作为语言名解析，不应崩溃
    func testParseCodeBlockWithSpacesInLanguageLineDoesNotCrash() {
        let content = """
        ```not a language
        code
        ```
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 1-6 级标题均能正确解析，不崩溃
    func testParseAllHeadingLevelsDoesNotCrash() {
        let levels = ["#", "##", "###", "####", "#####", "######"]
        for level in levels {
            let view = MarkdownText(content: "\(level) 标题")
            _ = view.body
        }
    }

    /// 任务列表（含 [x] / [ ] / [X]）不应导致解析崩溃
    func testParseTaskListDoesNotCrash() {
        let content = """
        - [x] 已完成
        - [ ] 未完成
        - [X] 大写X已完成
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 表格行不应导致解析崩溃
    func testParseTableDoesNotCrash() {
        let content = """
        | 姓名 | 年龄 |
        |---|---|
        | Alice | 30 |
        | Bob | 25 |
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 混合内容（标题 + 文本 + 任务列表 + 代码块 + 表格）不应崩溃
    func testParseMixedContentDoesNotCrash() {
        let content = """
        # 标题

        这是一段文本。

        - [x] 任务一
        - [ ] 任务二

        ```python
        print("hello")
        ```

        | 列1 | 列2 |
        |---|---|
        | a | b |
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 多个代码块交替文本段不应崩溃
    func testParseMultipleCodeBlocksDoesNotCrash() {
        let content = """
        ```swift
        let a = 1
        ```
        中间文本
        ```python
        b = 2
        ```
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 仅有代码块分隔符（未闭合）不应崩溃
    func testParseUnclosedCodeBlockDoesNotCrash() {
        let content = "```swift\nlet x = 42"
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 空代码块不应崩溃
    func testParseEmptyCodeBlockDoesNotCrash() {
        let content = """
        ```swift
        ```
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 仅含空白字符的文本不应崩溃
    func testParseWhitespaceOnlyTextDoesNotCrash() {
        let view = MarkdownText(content: "   \n  \n   ")
        _ = view.body
    }

    /// 标题或任务列表文本中包含 emoji / 多字节 Unicode 时不应崩溃
    /// 回归测试：解析器曾强制解包 Range(match.range(at:), in: line)，
    /// 当 NSRegularExpression 返回的 UTF-16 range 无法对齐 Swift String 的
    /// grapheme cluster 边界时会触发崩溃。
    func testParseEmojiInHeadingAndTaskListDoesNotCrash() {
        let content = """
        # 标题 👨‍👩‍👧‍👦

        - [x] 完成家庭任务 🏠
        - [ ] 购买牛奶 🥛
        ## 二级标题 🚀
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }

    /// 肤色修饰符、国旗、组合字符等复杂 grapheme cluster 不应导致崩溃
    func testParseComplexGraphemeClustersDoesNotCrash() {
        let content = """
        # 👋🏽 你好 🇨🇳
        - [x] 测试 ✍🏻
        """
        let view = MarkdownText(content: content)
        _ = view.body
    }
}
