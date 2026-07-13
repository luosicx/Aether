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

    // MARK: - URL scheme 校验测试

    /// navigate 仅允许 http/https URL，拒绝 file:// scheme
    func testNavigateRejectsFileScheme() async throws {
        let result = try await tool.execute(arguments: [
            "action": "navigate",
            "url": "file:///etc/passwd"
        ])
        XCTAssertEqual(result, "错误：仅允许 http/https URL")
    }

    /// navigate 拒绝 javascript: scheme
    func testNavigateRejectsJavascriptScheme() async throws {
        let result = try await tool.execute(arguments: [
            "action": "navigate",
            "url": "javascript:alert(1)"
        ])
        XCTAssertEqual(result, "错误：仅允许 http/https URL")
    }

    /// new_tab 拒绝非 http/https scheme
    func testNewTabRejectsFileScheme() async throws {
        let result = try await tool.execute(arguments: [
            "action": "new_tab",
            "url": "file:///tmp/test"
        ])
        XCTAssertEqual(result, "错误：仅允许 http/https URL")
    }

    /// navigate 缺少 url 参数应返回错误
    func testNavigateMissingUrl() async throws {
        let result = try await tool.execute(arguments: ["action": "navigate"])
        XCTAssertEqual(result, "错误：请提供 url 参数")
    }

    // MARK: - AppleScript 注入防护测试

    /// navigate 的 url 包含双引号时不应产生 AppleScript 注入
    /// 验证：包含双引号的 URL 被正确处理（不会执行注入的代码）
    func testNavigateEscapesDoubleQuotes() async throws {
        // 构造注入尝试：双引号闭合后注入 do shell script
        let maliciousURL = "https://evil.com\" & (do shell script \"id\") & \""
        let result = try await tool.execute(arguments: [
            "action": "navigate",
            "url": maliciousURL
        ])
        // URL 解析会因双引号失败 scheme 校验，或 AppleScript 执行时转义生效
        // 无论哪种情况，都不应执行注入的命令
        XCTAssertTrue(
            result.contains("错误") || result.contains("失败"),
            "包含双引号的 URL 不应导致代码执行：\(result)"
        )
    }
}
#endif
