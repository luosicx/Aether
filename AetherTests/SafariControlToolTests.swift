#if os(macOS)
import XCTest
@testable import Aether

final class SafariControlToolTests: XCTestCase {
    private let tool = SafariControlTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "control_safari")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteUnsupportedAction() async throws {
        let result = try await tool.execute(arguments: ["action": "unknown"])
        XCTAssertTrue(result.hasPrefix("错误"))
    }

    func testRunJSDisabled() async throws {
        let result = try await tool.execute(arguments: [
            "action": "run_js",
            "script": "alert(1)"
        ])
        XCTAssertEqual(result, "错误：run_js 操作已被禁用")
    }

    func testNavigateRejectsFileURL() async throws {
        let result = try await tool.execute(arguments: [
            "action": "navigate",
            "url": "file:///etc/passwd"
        ])
        XCTAssertTrue(result.hasPrefix("错误：不允许的 URL"))
    }

    func testNavigateRejectsHTTP() async throws {
        let result = try await tool.execute(arguments: [
            "action": "navigate",
            "url": "http://evil.com"
        ])
        XCTAssertTrue(result.hasPrefix("错误：不允许的 URL"))
    }

    func testNavigateAllowsWhitelistedHTTPS() async throws {
        let result = try await tool.execute(arguments: [
            "action": "navigate",
            "url": "https://chat.openai.com"
        ])
        XCTAssertFalse(result.hasPrefix("错误：不允许的 URL"))
    }

    func testNewTabRejectsNonWhitelistedHTTPS() async throws {
        let result = try await tool.execute(arguments: [
            "action": "new_tab",
            "url": "https://example.com"
        ])
        XCTAssertTrue(result.hasPrefix("错误：不允许的 URL"))
    }
}
#endif
