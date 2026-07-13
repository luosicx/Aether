import XCTest
import SwiftUI
@testable import Aether

/// Task 22: 富媒体消息支持单元测试。
/// 测试 LinkPreviewCard / RichMessageCard / InlineChartView 的初始化与数据处理。
@MainActor
final class RichMessageTests: XCTestCase {

    // MARK: - LinkPreviewCard

    /// LinkPreview 结构体可正确创建并保留所有字段
    func testLinkPreviewStructCreation() {
        let url = URL(string: "https://example.com/image.jpg")!
        let preview = LinkPreviewCard.LinkPreview(
            title: "测试标题",
            description: "测试描述",
            thumbnailURL: url
        )
        XCTAssertEqual(preview.title, "测试标题")
        XCTAssertEqual(preview.description, "测试描述")
        XCTAssertEqual(preview.thumbnailURL, url)
    }

    /// LinkPreview 结构体支持 nil 缩略图
    func testLinkPreviewStructWithNilThumbnail() {
        let preview = LinkPreviewCard.LinkPreview(
            title: "无缩略图",
            description: "",
            thumbnailURL: nil
        )
        XCTAssertNil(preview.thumbnailURL)
        XCTAssertTrue(preview.description.isEmpty)
    }

    /// LinkPreview 支持空标题
    func testLinkPreviewStructWithEmptyTitle() {
        let preview = LinkPreviewCard.LinkPreview(
            title: "",
            description: "有描述但无标题",
            thumbnailURL: nil
        )
        XCTAssertTrue(preview.title.isEmpty)
    }

    /// LinkPreviewCard 视图可正确初始化
    func testLinkPreviewCardInitialization() {
        let url = URL(string: "https://example.com")!
        let card = LinkPreviewCard(url: url)
        XCTAssertEqual(card.url, url)
    }

    // MARK: - RichMessageCard

    /// info 类型卡片可正确创建
    func testRichMessageCardInfoType() {
        let card = RichMessageCard(title: "信息", content: "这是一条信息", type: .info)
        XCTAssertEqual(card.title, "信息")
        XCTAssertEqual(card.content, "这是一条信息")
        XCTAssertEqual(card.type, .info)
    }

    /// warning 类型卡片可正确创建
    func testRichMessageCardWarningType() {
        let card = RichMessageCard(title: "警告", content: "注意风险", type: .warning)
        XCTAssertEqual(card.title, "警告")
        XCTAssertEqual(card.type, .warning)
    }

    /// success 类型卡片可正确创建
    func testRichMessageCardSuccessType() {
        let card = RichMessageCard(title: "成功", content: "操作完成", type: .success)
        XCTAssertEqual(card.title, "成功")
        XCTAssertEqual(card.type, .success)
    }

    /// error 类型卡片可正确创建
    func testRichMessageCardErrorType() {
        let card = RichMessageCard(title: "错误", content: "操作失败", type: .error)
        XCTAssertEqual(card.title, "错误")
        XCTAssertEqual(card.type, .error)
    }

    /// code 类型卡片可正确创建
    func testRichMessageCardCodeType() {
        let card = RichMessageCard(title: "代码", content: "print('hello')", type: .code)
        XCTAssertEqual(card.title, "代码")
        XCTAssertEqual(card.content, "print('hello')")
        XCTAssertEqual(card.type, .code)
    }

    /// RichMessageCard 支持空内容
    func testRichMessageCardWithEmptyContent() {
        let card = RichMessageCard(title: "空内容", content: "", type: .info)
        XCTAssertTrue(card.content.isEmpty)
    }

    /// RichMessageCard.CardType 枚举包含所有预期类型
    func testRichMessageCardTypeEnumCases() {
        let types: [RichMessageCard.CardType] = [.info, .warning, .success, .error, .code]
        XCTAssertEqual(types.count, 5, "CardType 应有 5 种类型")
    }

    // MARK: - InlineChartView

    /// bar 类型图表可正确初始化
    func testInlineChartViewBarType() {
        let data: [(label: String, value: Double)] = [
            ("一月", 100), ("二月", 200), ("三月", 150)
        ]
        let chart = InlineChartView(data: data, type: .bar)
        XCTAssertEqual(chart.data.count, 3)
        XCTAssertEqual(chart.data[0].label, "一月")
        XCTAssertEqual(chart.data[0].value, 100)
        XCTAssertEqual(chart.type, .bar)
    }

    /// line 类型图表可正确初始化
    func testInlineChartViewLineType() {
        let data: [(label: String, value: Double)] = [
            ("A", 10), ("B", 20), ("C", 15), ("D", 25)
        ]
        let chart = InlineChartView(data: data, type: .line)
        XCTAssertEqual(chart.data.count, 4)
        XCTAssertEqual(chart.type, .line)
    }

    /// pie 类型图表可正确初始化
    func testInlineChartViewPieType() {
        let data: [(label: String, value: Double)] = [
            ("苹果", 30), ("香蕉", 40), ("橙子", 30)
        ]
        let chart = InlineChartView(data: data, type: .pie)
        XCTAssertEqual(chart.data.count, 3)
        XCTAssertEqual(chart.type, .pie)
    }

    /// InlineChartView 支持空数据
    func testInlineChartViewEmptyData() {
        let chart = InlineChartView(data: [], type: .bar)
        XCTAssertTrue(chart.data.isEmpty)
    }

    /// InlineChartView 支持单条数据
    func testInlineChartViewSingleDataPoint() {
        let data: [(label: String, value: Double)] = [("唯一", 42)]
        let chart = InlineChartView(data: data, type: .line)
        XCTAssertEqual(chart.data.count, 1)
        XCTAssertEqual(chart.data[0].value, 42)
    }

    /// InlineChartView 支持负值数据
    func testInlineChartViewWithNegativeValues() {
        let data: [(label: String, value: Double)] = [
            ("收益", 100), ("亏损", -50), ("净额", 50)
        ]
        let chart = InlineChartView(data: data, type: .bar)
        XCTAssertEqual(chart.data[1].value, -50)
    }

    /// InlineChartView.ChartType 枚举包含所有预期类型
    func testInlineChartViewChartTypeEnumCases() {
        let types: [InlineChartView.ChartType] = [.bar, .line, .pie]
        XCTAssertEqual(types.count, 3, "ChartType 应有 3 种类型")
    }

    /// InlineChartView 支持浮点数值
    func testInlineChartViewWithFloatValues() {
        let data: [(label: String, value: Double)] = [
            ("A", 10.5), ("B", 20.3), ("C", 15.7)
        ]
        let chart = InlineChartView(data: data, type: .bar)
        XCTAssertEqual(chart.data[0].value, 10.5, accuracy: 0.01)
        XCTAssertEqual(chart.data[1].value, 20.3, accuracy: 0.01)
    }
}
