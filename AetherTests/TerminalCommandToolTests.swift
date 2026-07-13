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

    // MARK: - 命令解析

    func testParseWhitelistCommand() throws {
        let parsed = try TerminalCommandTool.parseCommand("ls -la /tmp")
        XCTAssertEqual(parsed.executableURL.lastPathComponent, "ls")
        XCTAssertEqual(parsed.arguments, ["-la", "/tmp"])
    }

    func testParseQuotedSpaces() throws {
        let parsed = try TerminalCommandTool.parseCommand("ls -la \"/path/with spaces\"")
        XCTAssertEqual(parsed.executableURL.lastPathComponent, "ls")
        XCTAssertEqual(parsed.arguments, ["-la", "/path/with spaces"])
    }

    func testParseSingleQuotes() throws {
        let parsed = try TerminalCommandTool.parseCommand("echo 'hello world'")
        XCTAssertEqual(parsed.executableURL.lastPathComponent, "echo")
        XCTAssertEqual(parsed.arguments, ["hello world"])
    }

    func testParseEmptyQuotedArgument() throws {
        let parsed = try TerminalCommandTool.parseCommand("echo \"\"")
        XCTAssertEqual(parsed.arguments, [""])
    }

    // MARK: - 白名单与拒绝规则

    func testNonWhitelistCommandRejected() {
        assertParseThrows("bash -c ls", expected: .notInWhitelist)
    }

    func testPipeRejected() {
        assertParseThrows("ls | cat", expected: .shellMetacharacter)
    }

    func testOutputRedirectRejected() {
        assertParseThrows("echo hello > file", expected: .shellMetacharacter)
    }

    func testInputRedirectRejected() {
        assertParseThrows("cat < file", expected: .shellMetacharacter)
    }

    func testSemicolonRejected() {
        assertParseThrows("ls; pwd", expected: .shellMetacharacter)
    }

    func testBackgroundRejected() {
        assertParseThrows("ls &", expected: .shellMetacharacter)
    }

    func testAndOperatorRejected() {
        assertParseThrows("ls && pwd", expected: .shellMetacharacter)
    }

    func testOrOperatorRejected() {
        assertParseThrows("ls || pwd", expected: .shellMetacharacter)
    }

    func testBacktickRejected() {
        assertParseThrows("echo `ls`", expected: .shellMetacharacter)
    }

    func testCommandSubstitutionRejected() {
        assertParseThrows("echo $(ls)", expected: .shellMetacharacter)
    }

    func testVariableExpansionRejected() {
        assertParseThrows("echo $HOME", expected: .shellMetacharacter)
    }

    func testGlobWildcardRejected() {
        assertParseThrows("ls *.txt", expected: .shellMetacharacter)
    }

    func testQuestionWildcardRejected() {
        assertParseThrows("ls ?", expected: .shellMetacharacter)
    }

    func testBase64BypassRejected() {
        assertParseThrows("base64 -d SGVsbG8K", expected: .base64Bypass)
    }

    func testBase64BypassWithPipeRejected() {
        assertParseThrows("echo SGVsbG8K | base64 -d", expected: .shellMetacharacter)
    }

    func testPathTraversalInArgumentsRejected() {
        assertParseThrows("ls ../../etc/passwd", expected: .pathTraversal)
    }

    func testSensitivePathRejected() {
        // 敏感路径黑名单：~/.ssh 应被拒绝
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sshPath = "\(home)/.ssh/id_rsa"
        assertParseThrows("ls \(sshPath)", expected: .pathTraversal)
    }

    func testCatRemovedFromWhitelist() {
        // cat 已从白名单移除，防止读取任意敏感文件
        assertParseThrows("cat /etc/passwd", expected: .notInWhitelist)
    }

    func testAbsolutePathExecutableRejected() {
        assertParseThrows("/bin/ls", expected: .pathTraversal)
    }

    func testRelativePathExecutableRejected() {
        assertParseThrows("./script", expected: .pathTraversal)
    }

    func testNoProcessInstantiationForRejectedInput() async throws {
        var factoryCalled = false
        let localTool = TerminalCommandTool()
        localTool.processFactory = {
            factoryCalled = true
            return Process()
        }
        let result = try await localTool.execute(arguments: ["command": "rm -rf /"])
        XCTAssertFalse(factoryCalled, "被拒绝的输入不应实例化 Process")
        XCTAssertEqual(result, "错误：禁止执行危险命令")
    }

    // MARK: - Helpers

    private func assertParseThrows(
        _ command: String,
        expected: TerminalCommandTool.ValidationError,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try TerminalCommandTool.parseCommand(command), file: file, line: line) { error in
            guard let validationError = error as? TerminalCommandTool.ValidationError else {
                XCTFail("期望 ValidationError，实际为 \(type(of: error))", file: file, line: line)
                return
            }
            XCTAssertEqual(validationError, expected, file: file, line: line)
        }
    }
}
#endif
