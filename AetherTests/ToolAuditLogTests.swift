import XCTest
@testable import Aether

/// ToolAuditLog 单元测试
@MainActor
final class ToolAuditLogTests: XCTestCase {
    private var defaults: UserDefaults!
    private var log: ToolAuditLog!
    private let suiteName = "ToolAuditLogTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        log = ToolAuditLog(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        log = nil
        defaults = nil
        super.tearDown()
    }

    /// 记录后应能从内存读取，且敏感参数被脱敏
    func testRecordAndRead() {
        log.record(toolName: "run_terminal_command", parameters: ["command": "rm -rf /"], decision: .deny)
        XCTAssertEqual(log.count, 1)

        let entries = log.recentEntries()
        XCTAssertEqual(entries.first?.toolName, "run_terminal_command")
        XCTAssertEqual(entries.first?.userDecision, .deny)
        XCTAssertTrue(entries.first?.redactedParameters.contains("***") == true, "敏感参数应被脱敏")
        XCTAssertFalse(entries.first?.redactedParameters.contains("rm -rf /") == true, "原始命令不应泄露")
    }

    /// 多条记录按时间倒序返回
    func testRecentEntriesOrder() {
        log.record(toolName: "a", parameters: [:], decision: .allowOnce)
        log.record(toolName: "b", parameters: [:], decision: .alwaysAllow)
        let entries = log.recentEntries()
        XCTAssertEqual(entries.map(\.toolName), ["b", "a"])
    }

    /// clear 后日志为空
    func testClear() {
        log.record(toolName: "test", parameters: [:], decision: .deny)
        log.clear()
        XCTAssertEqual(log.count, 0)
        XCTAssertTrue(log.recentEntries().isEmpty)
    }

    /// 持久化：新实例应能读取之前写入的记录
    func testPersistence() {
        log.record(toolName: "run_applescript", parameters: ["script": "tell app \"Finder\" to quit"], decision: .allowOnce)
        let newLog = ToolAuditLog(defaults: defaults)
        XCTAssertEqual(newLog.count, 1)
        XCTAssertEqual(newLog.recentEntries().first?.toolName, "run_applescript")
    }

    /// 脱敏器对已知敏感键替换为 ***
    func testRedaction() {
        let redacted = ToolParameterRedactor.redact(parameters: [
            "command": "secret-cmd",
            "script": "secret-script",
            "url": "https://example.com",
            "action": "delete",
            "display_id": 1
        ])
        XCTAssertTrue(redacted.contains("\"command\":\"***\""), "command 应被脱敏")
        XCTAssertTrue(redacted.contains("\"script\":\"***\""), "script 应被脱敏")
        XCTAssertTrue(redacted.contains("\"url\":\"***\""), "url 应被脱敏")
        XCTAssertTrue(redacted.contains("\"action\":\"delete\""), "action 不应被脱敏")
        XCTAssertTrue(redacted.contains("\"display_id\":\"1\""), "display_id 不应被脱敏")
    }
}
