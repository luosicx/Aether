import XCTest
@testable import Aether

/// LocationTool 单元测试
/// 注：定位依赖设备权限与环境，测试可能成功或返回错误字符串，仅校验不崩溃且返回非空字符串
final class LocationToolTests: XCTestCase {
    private let tool = LocationTool()

    /// definition：name == "get_location"，parameters 为空对象，required 为空
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "get_location")
        XCTAssertEqual(def.parameters["type"] as? String, "object")
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertTrue(properties?.isEmpty ?? true, "properties 应为空")
        let required = def.parameters["required"] as? [String]
        XCTAssertTrue(required?.isEmpty ?? false, "required 应为空")
    }

    /// execute 调用：在测试环境下定位可能成功或失败（权限/超时），仅校验返回非空字符串，
    /// 且内容包含位置或定位相关信息
    func testExecuteReturnsLocationOrError() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
        // 成功返回 "当前位置..." 或失败返回 "定位权限未授权..." / "定位超时..." / "定位失败..."
        XCTAssertTrue(result.contains("当前位置") || result.contains("定位"),
                      "结果应包含位置或定位相关信息，实际：\(result)")
    }

    /// execute 返回值类型为 String 且非空
    func testExecuteReturnsString() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: [:])
        let anyResult: Any = result
        XCTAssertTrue(anyResult is String, "execute 返回值应为 String 类型")
        XCTAssertFalse(result.isEmpty, "返回字符串不应为空")
    }
}
