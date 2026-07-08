import XCTest
@testable import AIBuilder

@MainActor
final class ClipboardToolTests: XCTestCase {
    private let readTool = ReadClipboardTool()
    private let writeTool = WriteClipboardTool()

    func testReadDefinitionSchema() {
        XCTAssertEqual(readTool.definition.name, "read_clipboard")
    }

    func testWriteDefinitionSchema() {
        XCTAssertEqual(writeTool.definition.name, "write_clipboard")
        let required = writeTool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("text") == true)
    }

    func testWriteThenRead() async throws {
        _ = try await writeTool.execute(arguments: ["text": "test123"])
        let result = try await readTool.execute(arguments: [:])
        XCTAssertEqual(result, "test123")
    }

    func testWriteMissingText() async throws {
        let result = try await writeTool.execute(arguments: [:])
        XCTAssertTrue(result.hasPrefix("错误"))
    }
}
