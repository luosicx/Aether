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

    func testExecuteEchoCommand() async throws {
        let result = try await tool.execute(arguments: ["command": "echo hello"])
        XCTAssertEqual(result.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testExecuteDangerousCommand() async throws {
        let result = try await tool.execute(arguments: ["command": "rm -rf /"])
        XCTAssertEqual(result, "错误：禁止执行危险命令")
    }

    func testExecuteDangerousCommandBypasses() async throws {
        let bypasses = [
            "rm  -rf  /",           // 多余空格
            "rm -rf --no-preserve-root /",
            "rm -rf \"$HOME\"",     // 引号包裹
            "rm -rf '$HOME'",
            "rm -rf $HOME/",
            "rm -rf ~/*",
            "dd  if=/dev/zero",
        ]
        for command in bypasses {
            let result = try await tool.execute(arguments: ["command": command])
            XCTAssertEqual(result, "错误：禁止执行危险命令", "命令应被拦截: \(command)")
        }
    }

    func testExecuteStderrCommand() async throws {
        let result = try await tool.execute(arguments: ["command": "ls /nonexistent"])
        XCTAssertTrue(result.contains("No such file"), "实际：\(result)")
    }
}
#endif
