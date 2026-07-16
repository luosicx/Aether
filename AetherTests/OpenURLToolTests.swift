import XCTest
@testable import Aether

/// OpenURLTool 单元测试
@MainActor
final class OpenURLToolTests: XCTestCase {
    private let tool = OpenURLTool()

    /// definition：name = "open_url"，required 含 "url"
    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "open_url")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("url") == true)
    }

    /// 缺 url 参数：返回错误字符串
    func testExecuteMissingURL() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 URL")
    }

    /// url 含空格导致 URL(string:) 初始化失败：返回错误字符串
    func testExecuteInvalidURL() async throws {
        let result = try await tool.execute(arguments: ["url": "not a url"])
        XCTAssertTrue(result.hasPrefix("错误：URL 无效"), "实际：\(result)")
    }

    /// file:// scheme 不在白名单内：拒绝执行
    func testExecuteFileSchemeRejected() async throws {
        let result = try await tool.execute(arguments: ["url": "file:///etc/passwd"])
        XCTAssertTrue(result.hasPrefix("错误"), "file:// 应被拒绝，实际：\(result)")
    }

    /// javascript: scheme 不在白名单内：拒绝执行
    func testExecuteJavascriptSchemeRejected() async throws {
        let result = try await tool.execute(arguments: ["url": "javascript:alert(1)"])
        XCTAssertTrue(result.hasPrefix("错误"), "javascript: 应被拒绝，实际：\(result)")
    }

    /// shortcuts:// scheme 不在白名单内：拒绝执行（防止绕过 run_shortcut 工具层授权）
    func testExecuteShortcutsSchemeRejected() async throws {
        let result = try await tool.execute(arguments: ["url": "shortcuts://run-shortcut?name=test"])
        XCTAssertTrue(result.hasPrefix("错误"), "shortcuts:// 应被拒绝，实际：\(result)")
    }

    /// mailto: scheme 在白名单内：允许
    func testExecuteMailtoAllowed() async throws {
        let result = try await tool.execute(arguments: ["url": "mailto:test@example.com"])
        XCTAssertEqual(result, "已打开 mailto:test@example.com")
    }

    /// 合法 URL：返回成功字符串（实际会触发系统打开动作）
    func testExecuteValidURL() async throws {
        let result = try await tool.execute(arguments: ["url": "https://www.apple.com"])
        XCTAssertEqual(result, "已打开 https://www.apple.com")
    }
}
