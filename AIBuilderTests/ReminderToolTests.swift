import XCTest
@testable import AIBuilder

/// ReminderTool 单元测试
/// 注：不测真实 EventKit 保存
final class ReminderToolTests: XCTestCase {
    private let tool = ReminderTool()

    /// definition：name = "create_reminder"，parameters.properties 含 "title"，required 含 "title"
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "create_reminder")
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["title"], "parameters.properties 应含 title 字段")
        let required = def.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("title") == true, "required 应含 title")
    }

    /// arguments 缺 title：实现返回错误字符串（前置校验在权限请求之前，故不触及 EventKit）
    /// 注：方法签名为 `async throws`，但该分支实际“返回而非抛错”
    func testExecuteMissingTitleThrows() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供提醒标题",
                       "缺 title 应返回错误字符串")
    }

    /// date 格式非 yyyy-MM-dd HH:mm 应返回错误字符串
    /// 实现在权限请求之前验证日期格式，无效时直接返回 "错误：日期格式无效"
    /// 故不依赖 EventKit 权限，测试稳定
    func testExecuteInvalidDateFormat() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": "not-a-date"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"),
                      "无效日期应返回错误字符串，实际：\(result)")
    }
}
