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
        XCTAssertTrue(result.hasPrefix("错误：URL 无效或缺少协议"))
    }

    /// 合法 https URL：返回成功字符串
    func testExecuteValidURL() async throws {
        let result = try await tool.execute(arguments: ["url": "https://www.apple.com"])
        XCTAssertEqual(result, "已打开 https://www.apple.com")
    }

    /// http 协议应在默认白名单内
    func testExecuteHTTPAllowed() async throws {
        let result = try await tool.execute(arguments: ["url": "http://example.com"])
        XCTAssertEqual(result, "已打开 http://example.com")
    }

    /// scheme 大小写不敏感，HTTPS 应被允许
    func testExecuteCaseInsensitiveScheme() async throws {
        let result = try await tool.execute(arguments: ["url": "HTTPS://example.com"])
        XCTAssertEqual(result, "已打开 HTTPS://example.com")
    }

    /// file:// 协议应被拒绝
    func testExecuteFileSchemeRejected() async throws {
        let result = try await tool.execute(arguments: ["url": "file:///etc/passwd"])
        XCTAssertTrue(result.contains("协议 'file' 不在白名单内"))
        XCTAssertTrue(result.contains("拒绝打开"))
    }

    /// 自定义协议应被拒绝
    func testExecuteCustomSchemeRejected() async throws {
        let result = try await tool.execute(arguments: ["url": "myapp://open?token=secret"])
        XCTAssertTrue(result.contains("协议 'myapp' 不在白名单内"))
        XCTAssertTrue(result.contains("拒绝打开"))
    }

    /// javascript: 伪协议应被拒绝
    func testExecuteJavaScriptSchemeRejected() async throws {
        let result = try await tool.execute(arguments: ["url": "javascript:alert(1)"])
        XCTAssertTrue(result.contains("协议 'javascript' 不在白名单内"))
        XCTAssertTrue(result.contains("拒绝打开"))
    }

    /// 缺少 scheme 的 URL 应被拒绝，且不会自动补全
    func testExecuteMissingSchemeRejected() async throws {
        let result = try await tool.execute(arguments: ["url": "www.apple.com"])
        XCTAssertTrue(result.hasPrefix("错误：URL 无效或缺少协议"))
    }

    /// 空字符串 URL 应被拒绝
    func testExecuteEmptyURLRejected() async throws {
        let result = try await tool.execute(arguments: ["url": ""])
        XCTAssertEqual(result, "错误：请提供 URL")
    }

    /// 自定义白名单：仅允许 mailto，则 mailto 可通过、https 被拒绝
    func testCustomAllowedSchemes() async throws {
        let customTool = OpenURLTool(allowedSchemes: ["mailto"])

        let allowedResult = try await customTool.execute(arguments: ["url": "mailto:test@example.com"])
        XCTAssertEqual(allowedResult, "已打开 mailto:test@example.com")

        let rejectedResult = try await customTool.execute(arguments: ["url": "https://example.com"])
        XCTAssertTrue(rejectedResult.contains("协议 'https' 不在白名单内"))
        XCTAssertTrue(rejectedResult.contains("拒绝打开"))
    }
}
