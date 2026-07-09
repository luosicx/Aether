#if os(macOS)
import XCTest
@testable import Aether

final class InputAutomationToolTests: XCTestCase {
    private let tool = InputAutomationTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "simulate_input")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteMissingParams() async throws {
        let result = try await tool.execute(arguments: ["action": "mouse_move"])
        XCTAssertTrue(result.hasPrefix("错误"))
    }
}
#endif
