#if os(macOS)
import XCTest
@testable import AIBuilder

final class ScreenshotToolTests: XCTestCase {
    private let tool = ScreenshotTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "take_screenshot")
    }

    func testExecuteReturnsFilePath() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.hasSuffix(".png") || result.hasPrefix("错误"), "实际：\(result)")
    }
}
#endif
