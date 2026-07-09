#if os(macOS)
import XCTest
@testable import Aether

final class AppManagementToolTests: XCTestCase {
    private let tool = AppManagementTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "manage_app")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteListRunning() async throws {
        let result = try await tool.execute(arguments: ["action": "list_running"])
        XCTAssertFalse(result.isEmpty)
    }

    func testExecuteFrontmost() async throws {
        let result = try await tool.execute(arguments: ["action": "frontmost"])
        XCTAssertFalse(result.isEmpty)
    }
}
#endif
