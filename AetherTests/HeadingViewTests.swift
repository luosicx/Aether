import XCTest
import SwiftUI
@testable import Aether

/// HeadingView 单元测试
///
/// 可测试内容：
/// - level / text 属性在初始化后被正确保留
/// - 通过访问 body 触发 attributedText 内联 Markdown 解析
///
/// 注意：`font` / `attributedText` 均为 private 计算属性，无法直接断言解析结果。
/// font 根据 level 选择不同字号字重（1=bold title / 2=bold title2 /
/// 3=semibold title3 / default=semibold body），但 Font 无法直接比较相等性。
@MainActor
final class HeadingViewTests: XCTestCase {

    // MARK: - View 初始化

    /// level 和 text 在初始化后被正确保留
    func testInitPreservesLevelAndText() {
        let view = HeadingView(level: 1, text: "标题")
        XCTAssertEqual(view.level, 1)
        XCTAssertEqual(view.text, "标题")
    }

    /// 1-6 级标题均可正常构造
    func testInitWithAllHeadingLevels() {
        for level in 1...6 {
            let view = HeadingView(level: level, text: "H\(level)")
            XCTAssertEqual(view.level, level)
            XCTAssertEqual(view.text, "H\(level)")
        }
    }

    /// 空文本可正常构造
    func testInitWithEmptyText() {
        let view = HeadingView(level: 2, text: "")
        XCTAssertEqual(view.text, "")
    }

    /// 超出常规范围的 level（如 0 / 7）也可构造，不崩溃
    func testInitWithOutOfRangeLevel() {
        let view0 = HeadingView(level: 0, text: "level 0")
        XCTAssertEqual(view0.level, 0)

        let view7 = HeadingView(level: 7, text: "level 7")
        XCTAssertEqual(view7.level, 7)
    }

    // MARK: - body smoke test（触发 attributedText Markdown 解析）

    /// 一级标题的 body 计算不崩溃
    func testBodyWithLevel1DoesNotCrash() {
        let view = HeadingView(level: 1, text: "一级标题")
        _ = view.body
    }

    /// 六级标题的 body 计算不崩溃
    func testBodyWithLevel6DoesNotCrash() {
        let view = HeadingView(level: 6, text: "六级标题")
        _ = view.body
    }

    /// 含内联 Markdown（粗体、链接、行内代码）的 body 计算不崩溃
    func testBodyWithInlineMarkdownDoesNotCrash() {
        let view = HeadingView(level: 3, text: "**粗体** 和 [链接](http://example.com) 及 `代码`")
        _ = view.body
    }

    /// 无效 Markdown 应回退为纯文本，不崩溃
    func testBodyWithInvalidMarkdownDoesNotCrash() {
        let view = HeadingView(level: 2, text: "普通文本 [未闭合链接")
        _ = view.body
    }

    /// 空文本的 body 计算不崩溃
    func testBodyWithEmptyTextDoesNotCrash() {
        let view = HeadingView(level: 1, text: "")
        _ = view.body
    }

    /// 1-6 级标题的 body 计算均不崩溃
    func testBodyWithAllLevelsDoesNotCrash() {
        for level in 1...6 {
            let view = HeadingView(level: level, text: "标题\(level)")
            _ = view.body
        }
    }

    /// H1/H2 会渲染分割线，H3-H6 不渲染，均不崩溃
    func testBodyWithDividerLevelsDoesNotCrash() {
        // level <= 2 时 VStack 中包含 Divider
        _ = HeadingView(level: 1, text: "H1").body
        _ = HeadingView(level: 2, text: "H2").body
        // level > 2 时不包含 Divider
        _ = HeadingView(level: 3, text: "H3").body
        _ = HeadingView(level: 4, text: "H4").body
    }

    /// 含特殊字符的文本不崩溃
    func testBodyWithSpecialCharactersDoesNotCrash() {
        let view = HeadingView(level: 2, text: "标题含 @#$%^&*() 特殊字符")
        _ = view.body
    }

    /// 超长文本不崩溃
    func testBodyWithLongTextDoesNotCrash() {
        let longText = String(repeating: "长", count: 500)
        let view = HeadingView(level: 1, text: longText)
        _ = view.body
    }
}
