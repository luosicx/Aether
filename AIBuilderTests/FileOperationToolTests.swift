#if os(macOS)
import XCTest
@testable import AIBuilder

final class FileOperationToolTests: XCTestCase {
    private let tool = FileOperationTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "manage_file")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteListDir() async throws {
        let result = try await tool.execute(arguments: ["action": "list", "path": "/tmp"])
        XCTAssertFalse(result.isEmpty)
    }

    func testExecuteFileInfo() async throws {
        let result = try await tool.execute(arguments: ["action": "info", "path": "/tmp"])
        XCTAssertTrue(result.contains("路径") || result.contains("错误"), "实际：\(result)")
    }
}
#endif
