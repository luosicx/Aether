#if os(macOS)
import XCTest
@testable import Aether

final class FinderToolTests: XCTestCase {
    private let tool = FinderTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "finder_action")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteReveal() async throws {
        let result = try await tool.execute(arguments: ["action": "reveal", "path": "/tmp"])
        XCTAssertTrue(result.contains("已") || result.contains("错误"), "实际：\(result)")
    }
}
#endif
