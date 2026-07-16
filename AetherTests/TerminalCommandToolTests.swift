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

    // MARK: - 大小写绕过防护测试（V5：APFS 大小写不敏感文件系统绕过）

    /// 敏感路径 home 段大小写变体应被拒绝。
    /// 安全审计 [V5] 指出：原大小写敏感的 hasPrefix 比较在 APFS（默认大小写不敏感）
    /// 上可被 /Users/Alice/.ssh 绕过 /Users/alice/.ssh。修复改为大小写不敏感比较。
    /// 此测试镜像 FileOperationToolTests 的同名测试，覆盖 TerminalCommandTool 的同名修复。
    func testSensitivePathCaseInsensitiveBypassRejected() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // 将 home 路径末段大写化，模拟大小写绕过：/Users/alice → /Users/ALICE
        let lastSegment = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        let capitalizedHome = home.replacingOccurrences(
            of: lastSegment,
            with: lastSegment.uppercased()
        )
        assertParseThrows("ls \(capitalizedHome)/.ssh/id_rsa", expected: .pathTraversal)
    }

    /// 敏感路径 .SSH 大写应被拒绝（与 FileOperationTool 的 .SSH 测试对齐）
    func testSensitivePathDotSSHUppercaseRejected() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        assertParseThrows("ls \(home)/.SSH/id_rsa", expected: .pathTraversal)
    }

    /// 敏感路径 .AWS 大写应被拒绝（覆盖 AWS 凭证泄露路径）
    func testSensitivePathDotAWSUppercaseRejected() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        assertParseThrows("ls \(home)/.AWS/credentials", expected: .pathTraversal)
    }

    /// 同时大写 home 段与敏感目录段也应被拒绝（组合绕过尝试）
    func testSensitivePathCombinedCaseBypassRejected() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lastSegment = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        let capitalizedHome = home.replacingOccurrences(
            of: lastSegment,
            with: lastSegment.uppercased()
        )
        assertParseThrows("ls \(capitalizedHome)/.SSH/id_rsa", expected: .pathTraversal)
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
