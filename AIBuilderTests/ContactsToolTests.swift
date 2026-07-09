import XCTest
@testable import Aether

final class ContactsToolTests: XCTestCase {
    private let tool = ContactsTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "search_contacts")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("query") == true)
    }

    func testExecuteMissingQuery() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供搜索关键词")
    }

    func testExecuteReturnsString() async throws {
        let result = try await tool.execute(arguments: ["query": "张"])
        XCTAssertFalse(result.isEmpty)
    }
}
