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

    // MARK: - definition 详细验证

    /// definition 的 properties 应包含所有参数
    func testDefinitionProperties() {
        let properties = tool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertNotNil(properties, "properties 应为字典")
        XCTAssertNotNil(properties?["action"], "应包含 action 属性")
        XCTAssertNotNil(properties?["x"], "应包含 x 属性")
        XCTAssertNotNil(properties?["y"], "应包含 y 属性")
        XCTAssertNotNil(properties?["from_x"], "应包含 from_x 属性")
        XCTAssertNotNil(properties?["from_y"], "应包含 from_y 属性")
        XCTAssertNotNil(properties?["to_x"], "应包含 to_x 属性")
        XCTAssertNotNil(properties?["to_y"], "应包含 to_y 属性")
        XCTAssertNotNil(properties?["text"], "应包含 text 属性")
        XCTAssertNotNil(properties?["key"], "应包含 key 属性")
        XCTAssertNotNil(properties?["modifiers"], "应包含 modifiers 属性")
        XCTAssertNotNil(properties?["delta_y"], "应包含 delta_y 属性")
    }

    /// definition 的 type 应为 object，required 应为 ["action"]
    func testDefinitionTypeAndRequired() {
        let type = tool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["action"])
    }

    // MARK: - mouse_move 错误处理

    /// mouse_move 缺少 x 和 y 应返回错误
    func testExecuteMouseMoveMissingParams() async throws {
        let result = try await tool.execute(arguments: ["action": "mouse_move"])
        XCTAssertEqual(result, "错误：请提供 x 和 y 参数")
    }

    /// mouse_move 只提供 x 缺少 y 应返回错误
    func testExecuteMouseMoveMissingY() async throws {
        let result = try await tool.execute(arguments: ["action": "mouse_move", "x": 100])
        XCTAssertEqual(result, "错误：请提供 x 和 y 参数")
    }

    // MARK: - mouse_click 错误处理

    /// mouse_click 缺少 x 和 y 应返回错误
    func testExecuteMouseClickMissingParams() async throws {
        let result = try await tool.execute(arguments: ["action": "mouse_click"])
        XCTAssertEqual(result, "错误：请提供 x 和 y 参数")
    }

    /// mouse_click 只提供 x 缺少 y 应返回错误
    func testExecuteMouseClickMissingY() async throws {
        let result = try await tool.execute(arguments: ["action": "mouse_click", "x": 100])
        XCTAssertEqual(result, "错误：请提供 x 和 y 参数")
    }

    // MARK: - mouse_drag 错误处理

    /// mouse_drag 缺少所有参数应返回错误
    func testExecuteMouseDragMissingAllParams() async throws {
        let result = try await tool.execute(arguments: ["action": "mouse_drag"])
        XCTAssertEqual(result, "错误：请提供 from_x, from_y, to_x, to_y 参数")
    }

    /// mouse_drag 只提供部分参数应返回错误
    func testExecuteMouseDragPartialParams() async throws {
        let result = try await tool.execute(arguments: ["action": "mouse_drag", "from_x": 0, "from_y": 0])
        XCTAssertEqual(result, "错误：请提供 from_x, from_y, to_x, to_y 参数")
    }

    // MARK: - key_type 错误处理

    /// key_type 缺少 text 参数应返回错误
    func testExecuteKeyTypeMissingText() async throws {
        let result = try await tool.execute(arguments: ["action": "key_type"])
        XCTAssertEqual(result, "错误：请提供 text 参数")
    }

    // MARK: - key_combo 错误处理

    /// key_combo 缺少 key 参数应返回错误
    func testExecuteKeyComboMissingKey() async throws {
        let result = try await tool.execute(arguments: ["action": "key_combo"])
        XCTAssertEqual(result, "错误：请提供 key 参数")
    }

    /// key_combo 提供未知按键应返回错误
    func testExecuteKeyComboUnknownKey() async throws {
        let result = try await tool.execute(arguments: ["action": "key_combo", "key": "unknown_key"])
        XCTAssertEqual(result, "错误：未知按键：unknown_key")
    }

    // MARK: - scroll 错误处理

    /// scroll 缺少 delta_y 参数应返回错误
    func testExecuteScrollMissingDeltaY() async throws {
        let result = try await tool.execute(arguments: ["action": "scroll"])
        XCTAssertEqual(result, "错误：请提供 delta_y 参数")
    }

    // MARK: - 不支持的 action

    /// 不支持的 action 应返回错误
    func testExecuteUnsupportedAction() async throws {
        let result = try await tool.execute(arguments: ["action": "unknown"])
        XCTAssertEqual(result, "错误：不支持的操作，支持 mouse_move/mouse_click/mouse_drag/key_type/key_combo/scroll")
    }

    /// action 不是 String 类型应返回错误
    func testExecuteActionNotString() async throws {
        let result = try await tool.execute(arguments: ["action": 123])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }
}
#endif
