#if os(macOS)
import XCTest
@testable import Aether

final class OCRToolTests: XCTestCase {
    private let tool = OCRTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "extract_text_from_image")
    }

    func testExecuteReturnsString() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty)
    }
}
#endif
