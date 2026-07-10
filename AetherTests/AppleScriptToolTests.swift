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
}
#endif
