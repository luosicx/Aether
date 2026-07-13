import XCTest
@testable import Aether

/// ToolAuditLogger 单元测试：验证审计日志的格式化与文件写入
final class ToolAuditLoggerTests: XCTestCase {
    private let logger = ToolAuditLogger.shared
    private var logFileURL: URL?

    override func setUp() {
        super.setUp()
        logFileURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("aether.tool.audit.log")
        // 清理旧日志文件
        if let url = logFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    override func tearDown() {
        if let url = logFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    /// log 方法应将包含工具名、授权状态和参数摘要的条目写入文件
    func testLogWritesEntryToFile() async throws {
        logger.log(
            toolName: "run_terminal_command",
            argumentsSummary: "command",
            authorized: true,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        // 等待异步文件写入完成
        let expectation = XCTestExpectation(description: "审计日志写入文件")
        var logContent = ""
        if let url = logFileURL {
            for _ in 0..<50 {
                if let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .utf8),
                   text.contains("run_terminal_command") {
                    logContent = text
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertTrue(logContent.contains("tool=run_terminal_command"), "日志应包含工具名")
        XCTAssertTrue(logContent.contains("authorized=true"), "日志应包含授权状态")
        XCTAssertTrue(logContent.contains("args=[command]"), "日志应包含参数摘要")
    }

    /// 多次 log 调用应追加写入，不覆盖之前的内容
    func testMultipleLogsAppendToFile() async throws {
        logger.log(toolName: "tool_a", argumentsSummary: "key1", authorized: true)
        logger.log(toolName: "tool_b", argumentsSummary: "key2", authorized: false)

        let expectation = XCTestExpectation(description: "两条审计日志均写入文件")
        var logContent = ""
        if let url = logFileURL {
            for _ in 0..<50 {
                if let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .utf8),
                   text.contains("tool_a") && text.contains("tool_b") {
                    logContent = text
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertTrue(logContent.contains("tool=tool_a"), "日志应包含第一条记录")
        XCTAssertTrue(logContent.contains("tool=tool_b"), "日志应包含第二条记录")
        // 验证追加写入：两条记录都应在文件中
        let lines = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 2, "应至少有 2 行日志")
    }

    /// authorized=false 时日志应正确记录未授权状态
    func testLogRecordsUnauthorizedStatus() async throws {
        logger.log(
            toolName: "read_clipboard",
            argumentsSummary: "",
            authorized: false,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        let expectation = XCTestExpectation(description: "未授权审计日志写入")
        var logContent = ""
        if let url = logFileURL {
            for _ in 0..<50 {
                if let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .utf8),
                   text.contains("read_clipboard") {
                    logContent = text
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertTrue(logContent.contains("authorized=false"), "日志应记录 authorized=false")
    }

    /// 日志条目应包含 ISO8601 格式的时间戳
    func testLogEntryContainsTimestamp() async throws {
        let testDate = Date(timeIntervalSince1970: 1700000000)
        logger.log(
            toolName: "test_tool",
            argumentsSummary: "args",
            authorized: true,
            timestamp: testDate
        )

        let expectation = XCTestExpectation(description: "带时间戳的日志写入")
        var logContent = ""
        if let url = logFileURL {
            for _ in 0..<50 {
                if let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .utf8),
                   text.contains("test_tool") {
                    logContent = text
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: 5.0)

        // ISO8601 格式应包含日期部分
        XCTAssertTrue(logContent.contains("2023"), "日志时间戳应包含年份")
    }
}
