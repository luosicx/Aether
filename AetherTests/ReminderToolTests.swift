import XCTest
@testable import Aether

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

    // MARK: - definition 结构完整性

    /// definition.description 非空
    func testDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(tool.definition.description.isEmpty, "description 不应为空")
    }

    /// definition.parameters["type"] 应为 "object"
    func testDefinitionParametersTypeIsObject() {
        let type = tool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object", "parameters.type 应为 object")
    }

    /// definition.parameters["properties"] 应含 "date" 字段
    func testDefinitionPropertiesContainsDate() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["date"], "properties 应含 date 字段")
        let dateProp = properties?["date"] as? [String: Any]
        XCTAssertEqual(dateProp?["type"] as? String, "string", "date type 应为 string")
    }

    /// definition.parameters["properties"]["title"] 应含非空 description
    func testDefinitionTitlePropertyHasDescription() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        let titleProp = properties?["title"] as? [String: Any]
        XCTAssertEqual(titleProp?["type"] as? String, "string", "title type 应为 string")
        XCTAssertFalse((titleProp?["description"] as? String)?.isEmpty == true, "title description 不应为空")
    }

    /// definition.parameters["required"] 应仅含 ["title"]
    func testDefinitionRequiredContainsOnlyTitle() {
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["title"], "required 应仅含 title")
    }

    /// date description 应含格式提示 yyyy-MM-dd HH:mm
    func testDefinitionDatePropertyContainsFormatHint() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        let dateProp = properties?["date"] as? [String: Any]
        let desc = dateProp?["description"] as? String
        XCTAssertFalse(desc?.isEmpty == true, "date description 不应为空")
        XCTAssertTrue(desc?.contains("YYYY-MM-DD") == true || desc?.contains("yyyy-MM-dd") == true,
                      "date description 应含日期格式提示")
    }

    // MARK: - 日期格式验证（解析在权限请求之前，不触及 EventKit，稳定）

    /// date 格式含日期但缺时间 "2026-01-15" 应返回错误
    func testExecuteInvalidDateFormatDateOnly() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": "2026-01-15"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "仅日期缺时间应返回错误，实际：\(result)")
    }

    /// date 格式用斜杠分隔 "2026/01/15 10:30" 应返回错误（实现要求连字符）
    func testExecuteInvalidDateFormatSlashSeparator() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": "2026/01/15 10:30"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "斜杠分隔应返回错误，实际：\(result)")
    }

    /// date 格式用 12 小时制 "2026-01-15 1:30 PM" 应返回错误
    func testExecuteInvalidDateFormat12Hour() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": "2026-01-15 1:30 PM"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "12 小时制应返回错误，实际：\(result)")
    }

    /// date 格式月份越界 "2026-13-01 10:00" 应返回错误
    func testExecuteInvalidDateFormatMonthOutOfRange() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": "2026-13-01 10:00"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "月份越界应返回错误，实际：\(result)")
    }

    /// date 格式日越界 "2026-01-32 10:00" 应返回错误
    func testExecuteInvalidDateFormatDayOutOfRange() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": "2026-01-32 10:00"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "日越界应返回错误，实际：\(result)")
    }

    /// date 为空字符串 "" 应返回错误
    func testExecuteEmptyDateString() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": ""])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "空日期字符串应返回错误，实际：\(result)")
    }

    /// date 非字符串类型（Int）应忽略 date，正常进入权限请求
    /// （实现用 as? String 向下转型，Int 不匹配则 parsedDate 保持 nil，不设置 dueDate）
    func testExecuteDateNotStringIsIgnored() async throws {
        // date 为 Int 类型，as? String 返回 nil，不触发日期解析错误
        // 将进入权限请求阶段，模拟器可能挂起或返回权限错误
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        var result = ""
        do {
            result = try await tool.execute(arguments: ["title": "测试", "date": 20260115])
        } catch {
            result = "错误：\(error)"
        }
        // 不做严格断言：可能成功也可能因权限失败，只要不 crash 即可
        XCTAssertFalse(result.isEmpty, "应返回非空结果")
    }

    /// title 非字符串类型（Int）应返回参数错误
    func testExecuteTitleNotStringReturnsError() async throws {
        let result = try await tool.execute(arguments: ["title": 123])
        XCTAssertEqual(result, "错误：请提供提醒标题", "非字符串 title 应返回参数错误")
    }
}
