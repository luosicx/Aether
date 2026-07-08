import XCTest
@testable import AIBuilder

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
        XCTAssertEqual(result, "错误：URL 无效")
    }

    /// 合法 URL：返回成功字符串（实际会触发系统打开动作）
    func testExecuteValidURL() async throws {
        let result = try await tool.execute(arguments: ["url": "https://www.apple.com"])
        XCTAssertEqual(result, "已打开 https://www.apple.com")
    }
}
