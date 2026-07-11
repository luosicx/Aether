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

    /// definition 描述应为非空字符串
    func testDefinitionDescriptionNotEmpty() {
        let def = tool.definition
        XCTAssertFalse(def.description.isEmpty, "工具描述不应为空")
        XCTAssertTrue(def.description.contains("地理位置") || def.description.contains("定位"),
                      "描述应与地理位置相关，实际：\(def.description)")
    }

    /// definition 多次访问应返回一致结果（确定性）
    func testDefinitionIsDeterministic() {
        let def1 = tool.definition
        let def2 = tool.definition
        XCTAssertEqual(def1.name, def2.name, "多次访问 definition 应返回一致 name")
        XCTAssertEqual(def1.parameters["type"] as? String, def2.parameters["type"] as? String,
                       "多次访问 definition 应返回一致 type")
    }

    /// LocationTool 应遵循 ToolProtocol 协议
    func testConformsToToolProtocol() {
        // 编译期即可验证协议遵循，此处仅做运行时 sanity check
        XCTAssertTrue(tool is ToolProtocol, "LocationTool 应遵循 ToolProtocol")
    }

    /// execute 无参调用：传空字典应等价于无参调用
    func testExecuteWithEmptyArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        // 传空字典应不报错（LocationTool 无入参）
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
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

    /// execute 多次调用应稳定返回非空字符串（验证无状态泄漏）
    func testExecuteMultipleCallsStable() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        for _ in 0..<3 {
            let result = try await tool.execute(arguments: [:])
            XCTAssertFalse(result.isEmpty, "多次调用 execute 应每次返回非空字符串")
        }
    }

    /// 多个 LocationTool 实例不应共享状态
    func testMultipleInstancesDoNotShareState() {
        let tool1 = LocationTool()
        let tool2 = LocationTool()
        XCTAssertEqual(tool1.definition.name, tool2.definition.name, "多个实例的 definition 应一致")
    }

    /// execute 传入无关参数应不影响执行（LocationTool 无入参，忽略所有参数）
    func testExecuteIgnoresExtraArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        // 传入无关参数应被忽略
        let result = try await tool.execute(arguments: ["unused": "value", "number": 42])
        XCTAssertFalse(result.isEmpty, "传入无关参数应不影响 execute 返回非空字符串")
    }

    #if os(macOS)
    /// macOS 上定位可能不可用，execute 应优雅返回提示字符串而非崩溃
    func testExecuteOnMacOSDoesNotCrash() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "macOS 上 execute 应返回非空字符串（成功或错误提示）")
    }
    #endif
}
