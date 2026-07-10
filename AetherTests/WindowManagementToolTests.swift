#if os(macOS)
import XCTest
@testable import Aether

final class WindowManagementToolTests: XCTestCase {
    private let tool = WindowManagementTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "manage_window")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteListWindows() async throws {
        let result = try await tool.execute(arguments: ["action": "list"])
        XCTAssertFalse(result.isEmpty)
    }
}
#endif
