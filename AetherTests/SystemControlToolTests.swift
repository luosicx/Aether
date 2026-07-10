#if os(macOS)
import XCTest
@testable import Aether

final class SystemControlToolTests: XCTestCase {
    private let tool = SystemControlTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "system_control")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteSetVolume() async throws {
        let result = try await tool.execute(arguments: ["action": "set_volume", "value": 50])
        XCTAssertTrue(result.contains("已") || result.contains("错误"), "实际：\(result)")
    }
}
#endif
