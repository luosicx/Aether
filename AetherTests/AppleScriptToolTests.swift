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
        let original = AppleScriptTool.isEnabled
        defer { AppleScriptTool.isEnabled = original }
        AppleScriptTool.isEnabled = true
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 AppleScript 脚本")
    }

    func testExecuteDisabled() async throws {
        let original = AppleScriptTool.isEnabled
        defer { AppleScriptTool.isEnabled = original }
        AppleScriptTool.isEnabled = false
        let result = try await tool.execute(arguments: ["script": "return \"hello\""])
        XCTAssertEqual(result, "错误：AppleScript 工具未启用，请在设置中开启")
    }

    func testExecuteSimpleScript() async throws {
        let original = AppleScriptTool.isEnabled
        defer { AppleScriptTool.isEnabled = original }
        AppleScriptTool.isEnabled = true
        let result = try await tool.execute(arguments: ["script": "return \"hello\""])
        XCTAssertEqual(result, "hello")
    }

    func testExecuteScriptError() async throws {
        let original = AppleScriptTool.isEnabled
        defer { AppleScriptTool.isEnabled = original }
        AppleScriptTool.isEnabled = true
        let result = try await tool.execute(arguments: ["script": "invalid syntax {{{"])
        XCTAssertTrue(result.hasPrefix("AppleScript 执行失败"), "实际：\(result)")
    }
}
#endif
