#if os(macOS)
import XCTest
@testable import AIBuilder

final class SafariControlToolTests: XCTestCase {
    private let tool = SafariControlTool()
    
    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "control_safari")
    }
    
    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }
    
    func testExecuteUnsupportedAction() async throws {
        let result = try await tool.execute(arguments: ["action": "unknown"])
        XCTAssertTrue(result.hasPrefix("错误"))
    }
}
#endif
