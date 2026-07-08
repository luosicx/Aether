import XCTest
@testable import AIBuilder

/// WeatherTool 单元测试
/// 注：天气查询依赖网络与 Open-Meteo API，需联网的用例在网络不可用时跳过；
/// 定位相关用例在测试环境下可能成功或返回错误，仅校验不崩溃且返回非空字符串
final class WeatherToolTests: XCTestCase {
    private let tool = WeatherTool()

    /// definition：name == "get_weather"，properties 含 city 字段，required 为空
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "get_weather")
        XCTAssertEqual(def.parameters["type"] as? String, "object")
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["city"], "properties 应含 city 字段")
        let cityProp = properties?["city"] as? [String: Any]
        XCTAssertEqual(cityProp?["type"] as? String, "string", "city 字段 type 应为 string")
        XCTAssertNotNil(cityProp?["description"], "city 字段应含 description")
        let required = def.parameters["required"] as? [String]
        XCTAssertTrue(required?.isEmpty ?? false, "required 应为空")
    }

    /// execute 无参调用：走定位流程，可能返回天气或定位错误，仅校验返回非空字符串
    func testExecuteMissingCityReturnsLocationOrError() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "无参应返回非空字符串（天气或定位相关错误提示）")
    }

    /// execute 无效城市：应返回 "未找到城市"；网络不可用或 API 不可达时跳过
    func testExecuteInvalidCityReturnsNotFound() async throws {
        let result = try await tool.execute(arguments: ["city": "不存在的城市名xyz"])
        // 网络不可用或 API 不可达时，结果为 "天气查询失败：..."，跳过断言
        if result.contains("天气查询失败") {
            throw XCTSkip("网络不可用，跳过：\(result)")
        }
        XCTAssertTrue(result.contains("未找到城市"), "无效城市应返回未找到城市，实际：\(result)")
    }

    /// execute 返回值类型为 String 且非空（合法城市名查询，网络不可用跳过）
    func testExecuteReturnsString() async throws {
        let result = try await tool.execute(arguments: ["city": "上海"])
        if result.contains("天气查询失败") {
            throw XCTSkip("网络不可用，跳过：\(result)")
        }
        let anyResult: Any = result
        XCTAssertTrue(anyResult is String, "execute 返回值应为 String 类型")
        XCTAssertFalse(result.isEmpty, "应返回非空天气信息")
        XCTAssertTrue(result.contains("城市") || result.contains("未找到城市"),
                      "结果应含城市或未找到提示，实际：\(result)")
    }
}
