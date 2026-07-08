import XCTest
@testable import AIBuilder

/// Day 11: DateTimeTool 单元测试
final class DateTimeToolTests: XCTestCase {
    private let tool = DateTimeTool()

    @MainActor
    func testDefaultTimezone() async throws {
        let result = try await tool.execute(arguments: [:])
        // 应包含日期时间格式 yyyy-MM-dd HH:mm:ss
        XCTAssertTrue(result.contains("-"), "结果应含日期分隔符：\(result)")
        XCTAssertTrue(result.contains(":"), "结果应含时间分隔符：\(result)")
        // 长度至少 19（yyyy-MM-dd HH:mm:ss）
        XCTAssertGreaterThanOrEqual(result.count, 19, "结果长度不足：\(result)")
    }

    @MainActor
    func testSpecifiedTimezone() async throws {
        let result = try await tool.execute(arguments: ["timezone": "Asia/Shanghai"])
        // ZZZZ 在不同 iOS 版本可能返回 "GMT+8"、"GMT+08:00"、"+0800" 等
        // 只要含 GMT/+0800/+08 之一即视为指定时区生效
        let hasTimezone = result.contains("GMT+8") || result.contains("GMT+08")
            || result.contains("+0800") || result.contains("Asia/Shanghai")
            || result.contains("CST") || result.contains("China")
        XCTAssertTrue(hasTimezone, "结果应含上海时区标识：\(result)")
    }

    @MainActor
    func testInvalidTimezoneFallback() async throws {
        // 无效时区应回退到系统时区，不崩溃
        let result = try await tool.execute(arguments: ["timezone": "Invalid/Zone"])
        XCTAssertFalse(result.isEmpty, "无效时区应回退到系统时区，返回非空字符串")
    }
}
