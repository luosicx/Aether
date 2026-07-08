import XCTest
@testable import AIBuilder

final class ShortcutsToolTests: XCTestCase {
    private let runTool = RunShortcutTool()
    private let listTool = ListShortcutsTool()
    private let createTool = CreateShortcutTool()

    func testRunDefinitionSchema() {
        XCTAssertEqual(runTool.definition.name, "run_shortcut")
        let required = runTool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("name") == true)
    }

    func testListDefinitionSchema() {
        XCTAssertEqual(listTool.definition.name, "list_shortcuts")
    }

    func testCreateDefinitionSchema() {
        XCTAssertEqual(createTool.definition.name, "create_shortcut")
        let required = createTool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("name") == true)
        XCTAssertTrue(required?.contains("action") == true)
    }

    func testCreateMissingName() async throws {
        let result = try await createTool.execute(arguments: ["action": "open_url"])
        XCTAssertEqual(result, "错误：请提供快捷指令名称")
    }

    func testCreateUnsupportedAction() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "unknown"])
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/run_script/show_text/copy_to_clipboard")
    }

    func testCreateMissingAction() async throws {
        let result = try await createTool.execute(arguments: ["name": "test"])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }
}
