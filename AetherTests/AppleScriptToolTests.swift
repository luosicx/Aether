#if os(macOS)
import XCTest
@testable import Aether

final class AppleScriptToolTests: XCTestCase {
    private let tool = AppleScriptTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "run_applescript")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["action"])
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["action"], "应暴露 action 参数")
        XCTAssertNil(properties?["script"], "不应再暴露任意脚本参数")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    /// 旧 script 接口应被明确拒绝（不再执行任意 AppleScript）
    func testRawScriptIsRejected() async throws {
        let result = try await tool.execute(arguments: ["script": "return \"hello\""])
        XCTAssertTrue(result.contains("不再支持任意 AppleScript 脚本"), "实际：\(result)")
    }

    /// 未定义动作应被拒绝
    func testUnknownActionRejected() async throws {
        let result = try await tool.execute(arguments: ["action": "do_shell_script"])
        XCTAssertTrue(result.contains("不支持的动作"), "实际：\(result)")
    }

    /// get_system_version 应返回非空结果（固定模板，不依赖自动化权限）
    func testGetSystemVersionReturnsResult() async throws {
        let result = try await tool.execute(arguments: ["action": "get_system_version"])
        XCTAssertFalse(result.isEmpty, "系统版本结果不应为空")
        XCTAssertFalse(result.contains("无法编译脚本"), "固定模板应可编译：\(result)")
    }

    /// reveal_in_finder 应拒绝相对路径
    func testRevealRejectsRelativePath() async throws {
        let result = try await tool.execute(arguments: ["action": "reveal_in_finder", "path": "relative/path"])
        XCTAssertTrue(result.contains("绝对路径"), "实际：\(result)")
    }

    /// reveal_in_finder 应拒绝不存在的路径
    func testRevealRejectsNonexistentPath() async throws {
        let path = "/nonexistent/aether_\(UUID().uuidString)"
        let result = try await tool.execute(arguments: ["action": "reveal_in_finder", "path": path])
        XCTAssertTrue(result.contains("路径不存在"), "实际：\(result)")
    }

    /// open_url 应拒绝非 http/https scheme（file/javascript/ftp）
    func testOpenURLRejectsNonHTTPScheme() async throws {
        for url in ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com/x", "not a url"] {
            let result = try await tool.execute(arguments: ["action": "open_url", "url": url])
            XCTAssertEqual(result, "错误：仅支持合法的 http/https URL", "URL \(url) 应被拒绝")
        }
    }

    /// open_url 应拒绝可破坏 URL/AppleScript 解析的注入字符
    func testOpenURLRejectsInjectionPayload() async throws {
        let payload = "https://example.com/\" & (do shell script \"id\") & \""
        let result = try await tool.execute(arguments: ["action": "open_url", "url": payload])
        XCTAssertEqual(result, "错误：仅支持合法的 http/https URL", "实际：\(result)")
    }

    /// action 非 String 应返回参数错误
    func testActionNotString() async throws {
        let result = try await tool.execute(arguments: ["action": 123])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }
}
#endif
