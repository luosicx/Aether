import XCTest
@testable import AIBuilder

/// DeviceInfoTool 单元测试
final class DeviceInfoToolTests: XCTestCase {
    private let tool = DeviceInfoTool()

    /// definition：name == "get_device_info"，required 为空数组
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "get_device_info")
        let required = def.parameters["required"] as? [String]
        XCTAssertEqual(required, [], "required 应为空数组")
    }

    /// execute 返回结果应包含 "设备型号" 与 "系统版本"
    func testExecuteReturnsDeviceInfo() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.contains("设备型号"), "结果应含设备型号：\(result)")
        XCTAssertTrue(result.contains("系统版本"), "结果应含系统版本：\(result)")
    }

    /// execute 返回结果应包含 "可用存储"
    func testExecuteContainsStorage() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.contains("可用存储"), "结果应含可用存储：\(result)")
    }

    /// execute 返回结果应包含 "电量"，值不为空
    func testExecuteContainsBattery() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.contains("电量"), "结果应含电量：\(result)")
    }
}
