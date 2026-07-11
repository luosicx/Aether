#if os(macOS)
import XCTest
@testable import Aether

final class TerminalCommandToolTests: XCTestCase {
    private let tool = TerminalCommandTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "run_terminal_command")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("command") == true)
    }

    func testExecuteMissingCommand() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供要执行的命令")
    }

    func testExecuteWhitelistedCommandPwd() async throws {
        let result = try await tool.execute(arguments: ["command": "pwd"])
        XCTAssertEqual(result, FileManager.default.currentDirectoryPath)
    }

    func testExecuteWhitelistedCommandGitStatus() async throws {
        let result = try await tool.execute(arguments: ["command": "git status"])
        XCTAssertFalse(result.hasPrefix("错误：不允许执行的命令"), "白名单命令不应被拦截，实际：\(result)")
        XCTAssertFalse(result.isEmpty, "应有输出或错误信息")
    }

    func testExecuteWhitelistedCommandStderr() async throws {
        let result = try await tool.execute(arguments: ["command": "ls /nonexistent"])
        XCTAssertTrue(result.contains("No such file"), "实际：\(result)")
    }

    func testExecuteNonWhitelistedCommand() async throws {
        let result = try await tool.execute(arguments: ["command": "rm -rf /"])
        XCTAssertEqual(result, "错误：不允许执行的命令: rm -rf /")
    }

    func testExecuteInjectionAttemptsAreBlocked() async throws {
        let injections = [
            "echo rm -rf / | bash",
            "bash -c 'rm -rf /'",
            "git status; rm -rf /",
            "git status && rm -rf /"
        ]

        for command in injections {
            let result = try await tool.execute(arguments: ["command": command])

            switch command {
            case "echo rm -rf / | bash":
                XCTAssertEqual(result, "错误：不允许执行的命令: \(command)")
            case "bash -c 'rm -rf /'":
                XCTAssertEqual(result, "错误：不允许执行的命令: \(command)")
            case "git status; rm -rf /":
                XCTAssertTrue(result.contains("status;"), "注入应被阻止，实际：\(result)")
            case "git status && rm -rf /":
                XCTAssertTrue(result.contains("&&"), "注入应被阻止，实际：\(result)")
            default:
                break
            }

            XCTAssertFalse(result.contains("No such file"), "注入不应触发 rm 执行，实际：\(result)")
        }
    }
}
#endif
