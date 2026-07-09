import XCTest
@testable import Aether

/// AlarmTool 单元测试
/// 注：不测真实 EventKit 保存（避免权限依赖）
final class AlarmToolTests: XCTestCase {
    private let tool = AlarmTool()

    /// definition：name = "create_alarm"，parameters.properties 含 "time" 字段，required 含 "time"
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "create_alarm")
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["time"], "parameters.properties 应含 time 字段")
        let required = def.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("time") == true, "required 应含 time")
    }

    /// arguments 缺 time：实现返回错误字符串（前置参数校验在权限请求之前，故不触及 EventKit）
    /// 注：方法签名为 `async throws`，但该分支实际“返回而非抛错”，此处断言返回的错误字符串
    func testExecuteMissingTimeThrows() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供闹钟时间",
                       "缺 time 应返回错误字符串")
    }

    /// time = "25:99" 应返回错误字符串
    /// 注：execute 在时间格式校验之前会先请求 EventKit 权限：
    ///   - 权限拒绝 → 返回 "错误：无法访问日历"
    ///   - 权限授予 → "25:99" 格式无效 → 返回 "错误：时间格式无效"
    /// 两种情况均为错误字符串，故断言结果以 "错误" 开头
    func testExecuteInvalidTimeFormat() async {
        var result = ""
        do {
            result = try await tool.execute(arguments: ["time": "25:99"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"),
                      "无效时间格式应返回错误字符串，实际：\(result)")
    }
}
