import XCTest
@testable import Aether

/// MarkdownTableParser 单元测试：验证 Markdown 表格语法解析、对齐方式、边界情况。
final class MarkdownTableParserTests: XCTestCase {

    // MARK: - isTableRow

    func testIsTableRowWithPipePrefix() {
        XCTAssertTrue(MarkdownTableParser.isTableRow("| cell |"))
        XCTAssertTrue(MarkdownTableParser.isTableRow("  | cell |"))
        XCTAssertTrue(MarkdownTableParser.isTableRow("|cell|"))
    }

    func testIsTableRowWithoutPipePrefix() {
        XCTAssertFalse(MarkdownTableParser.isTableRow("cell"))
        XCTAssertFalse(MarkdownTableParser.isTableRow("  cell"))
        XCTAssertFalse(MarkdownTableParser.isTableRow(""))
    }

    // MARK: - isAlignmentRow

    func testIsAlignmentRowWithDashes() {
        XCTAssertTrue(MarkdownTableParser.isAlignmentRow("|---|---|"))
        XCTAssertTrue(MarkdownTableParser.isAlignmentRow("| --- | --- |"))
    }

    func testIsAlignmentRowWithColons() {
        XCTAssertTrue(MarkdownTableParser.isAlignmentRow("|:--|:-:|-:|"))
        XCTAssertTrue(MarkdownTableParser.isAlignmentRow("|:---|:---:|---:|"))
    }

    func testIsAlignmentRowNotAlignment() {
        XCTAssertFalse(MarkdownTableParser.isAlignmentRow("| header | header |"))
        XCTAssertFalse(MarkdownTableParser.isAlignmentRow("| abc | def |"))
        XCTAssertFalse(MarkdownTableParser.isAlignmentRow("not a row"))
        XCTAssertFalse(MarkdownTableParser.isAlignmentRow(""))
    }

    func testIsAlignmentRowRequiresDash() {
        // 只有冒号没有横线不合法
        XCTAssertFalse(MarkdownTableParser.isAlignmentRow("|::|"))
    }

    // MARK: - parseAlignment

    func testParseAlignmentLeft() {
        XCTAssertEqual(MarkdownTableParser.parseAlignment(":---"), .left)
        XCTAssertEqual(MarkdownTableParser.parseAlignment("---"), .left)
        XCTAssertEqual(MarkdownTableParser.parseAlignment(": -"), .left)
    }

    func testParseAlignmentRight() {
        XCTAssertEqual(MarkdownTableParser.parseAlignment("---:"), .right)
        XCTAssertEqual(MarkdownTableParser.parseAlignment("  ---:  "), .right)
    }

    func testParseAlignmentCenter() {
        XCTAssertEqual(MarkdownTableParser.parseAlignment(":---:"), .center)
        XCTAssertEqual(MarkdownTableParser.parseAlignment(": - :"), .center)
    }

    // MARK: - parseCells

    func testParseCellsStandard() {
        XCTAssertEqual(MarkdownTableParser.parseCells("| a | b | c |"), ["a", "b", "c"])
    }

    func testParseCellsNoLeadingPipe() {
        XCTAssertEqual(MarkdownTableParser.parseCells("a | b | c |"), ["a", "b", "c"])
    }

    func testParseCellsNoTrailingPipe() {
        XCTAssertEqual(MarkdownTableParser.parseCells("| a | b | c"), ["a", "b", "c"])
    }

    func testParseCellsNoPipes() {
        XCTAssertEqual(MarkdownTableParser.parseCells("a | b | c"), ["a", "b", "c"])
    }

    func testParseCellsSingleCell() {
        XCTAssertEqual(MarkdownTableParser.parseCells("| only |"), ["only"])
    }

    func testParseCellsEmptyCells() {
        XCTAssertEqual(MarkdownTableParser.parseCells("| | |"), ["", ""])
    }

    func testParseCellsTrimsWhitespace() {
        XCTAssertEqual(MarkdownTableParser.parseCells("|  hello  |  world  |"), ["hello", "world"])
    }

    // MARK: - parse (完整表格解析)

    func testParseStandardTable() {
        let lines = [
            "| Name | Age |",
            "|---|---|",
            "| Alice | 30 |",
            "| Bob | 25 |"
        ]
        guard let table = MarkdownTableParser.parse(lines) else {
            XCTFail("应解析成功")
            return
        }
        XCTAssertEqual(table.headers, ["Name", "Age"])
        XCTAssertEqual(table.alignments, [.left, .left])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0], ["Alice", "30"])
        XCTAssertEqual(table.rows[1], ["Bob", "25"])
    }

    func testParseTableWithAlignment() {
        let lines = [
            "| Name | Age | Score |",
            "|:---|---:|:---:|",
            "| Alice | 30 | 95 |"
        ]
        guard let table = MarkdownTableParser.parse(lines) else {
            XCTFail("应解析成功")
            return
        }
        XCTAssertEqual(table.headers, ["Name", "Age", "Score"])
        XCTAssertEqual(table.alignments, [.left, .right, .center])
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0], ["Alice", "30", "95"])
    }

    func testParseTableTooFewLines() {
        XCTAssertNil(MarkdownTableParser.parse([]), "空数组应返回 nil")
        XCTAssertNil(MarkdownTableParser.parse(["| header |"]), "仅一行应返回 nil")
    }

    func testParseTableWithoutAlignmentRow() {
        let lines = [
            "| Name | Age |",
            "| Alice | 30 |"
        ]
        XCTAssertNil(MarkdownTableParser.parse(lines), "第二行非对齐行应返回 nil")
    }

    func testParseSingleColumnTable() {
        let lines = [
            "| Name |",
            "|---|",
            "| Alice |"
        ]
        guard let table = MarkdownTableParser.parse(lines) else {
            XCTFail("应解析成功")
            return
        }
        XCTAssertEqual(table.headers, ["Name"])
        XCTAssertEqual(table.alignments, [.left])
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0], ["Alice"])
    }

    func testParseTableWithNoDataRows() {
        let lines = [
            "| Header |",
            "|---|"
        ]
        guard let table = MarkdownTableParser.parse(lines) else {
            XCTFail("应解析成功（仅表头 + 对齐行）")
            return
        }
        XCTAssertEqual(table.headers, ["Header"])
        XCTAssertEqual(table.rows.count, 0, "无数据行时 rows 应为空数组")
    }

    func testParseTablePadsShortRows() {
        let lines = [
            "| a | b | c |",
            "|---|---|---|",
            "| 1 |"
        ]
        guard let table = MarkdownTableParser.parse(lines) else {
            XCTFail("应解析成功")
            return
        }
        XCTAssertEqual(table.rows[0].count, 3, "短行应被补齐到表头列数")
        XCTAssertEqual(table.rows[0], ["1", "", ""])
    }

    func testParseTableWithExtraColumnsInDataRow() {
        let lines = [
            "| a | b |",
            "|---|---|",
            "| 1 | 2 | 3 |"
        ]
        guard let table = MarkdownTableParser.parse(lines) else {
            XCTFail("应解析成功")
            return
        }
        // 多余列不应被截断（parse 不截断，只补齐）
        XCTAssertEqual(table.rows[0].count, 3, "多余列应保留")
    }

    func testParseTableHeadersNonEmpty() {
        let lines = [
            "| header1 | header2 |",
            "|---|---|",
            "| data | data |"
        ]
        guard let table = MarkdownTableParser.parse(lines) else {
            XCTFail("应解析成功")
            return
        }
        XCTAssertFalse(table.headers.isEmpty)
        XCTAssertEqual(table.headers.count, 2)
    }

    func testParseTableIdentifiable() {
        let lines = [
            "| H |",
            "|---|",
            "| D |"
        ]
        let table1 = MarkdownTableParser.parse(lines)
        let table2 = MarkdownTableParser.parse(lines)
        XCTAssertNotNil(table1)
        XCTAssertNotNil(table2)
        XCTAssertNotEqual(table1!.id, table2!.id, "每次解析应产生唯一 UUID")
    }
}
