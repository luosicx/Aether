#if os(macOS)
import XCTest
@testable import Aether

final class WindowManagementToolTests: XCTestCase {
    private let tool = WindowManagementTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "manage_window")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteListWindows() async throws {
        let result = try await tool.execute(arguments: ["action": "list"])
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - definition 详细验证

    /// definition 的 properties 应包含 action/app/x/y/width/height
    func testDefinitionProperties() {
        let properties = tool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertNotNil(properties, "properties 应为字典")
        XCTAssertNotNil(properties?["action"], "应包含 action 属性")
        XCTAssertNotNil(properties?["app"], "应包含 app 属性")
        XCTAssertNotNil(properties?["x"], "应包含 x 属性")
        XCTAssertNotNil(properties?["y"], "应包含 y 属性")
        XCTAssertNotNil(properties?["width"], "应包含 width 属性")
        XCTAssertNotNil(properties?["height"], "应包含 height 属性")
    }

    /// definition 的 type 应为 object，required 应为 ["action"]
    func testDefinitionTypeAndRequired() {
        let type = tool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["action"])
    }

    // MARK: - focus 错误处理

    /// focus 缺少 app 参数应返回错误
    func testExecuteFocusMissingApp() async throws {
        let result = try await tool.execute(arguments: ["action": "focus"])
        XCTAssertEqual(result, "错误：请提供 app 参数")
    }

    /// focus 不存在的应用应返回未找到提示
    func testExecuteFocusNonExistentApp() async throws {
        let result = try await tool.execute(arguments: ["action": "focus", "app": "NonExistentApp12345"])
        XCTAssertTrue(result.contains("未找到") || result.contains("错误"),
                       "不存在的应用应返回未找到提示：\(result)")
    }

    // MARK: - move 错误处理

    /// move 缺少所有参数应返回错误
    func testExecuteMoveMissingAllParams() async throws {
        let result = try await tool.execute(arguments: ["action": "move"])
        XCTAssertEqual(result, "错误：请提供 app、x、y 参数")
    }

    /// move 只提供 app 缺少 x/y 应返回错误
    func testExecuteMoveMissingXY() async throws {
        let result = try await tool.execute(arguments: ["action": "move", "app": "TestApp"])
        XCTAssertEqual(result, "错误：请提供 app、x、y 参数")
    }

    /// move 只提供 app 和 x 缺少 y 应返回错误
    func testExecuteMoveMissingY() async throws {
        let result = try await tool.execute(arguments: ["action": "move", "app": "TestApp", "x": 100])
        XCTAssertEqual(result, "错误：请提供 app、x、y 参数")
    }

    // MARK: - resize 错误处理

    /// resize 缺少所有参数应返回错误
    func testExecuteResizeMissingAllParams() async throws {
        let result = try await tool.execute(arguments: ["action": "resize"])
        XCTAssertEqual(result, "错误：请提供 app、width、height 参数")
    }

    /// resize 只提供 app 缺少 width/height 应返回错误
    func testExecuteResizeMissingWidthHeight() async throws {
        let result = try await tool.execute(arguments: ["action": "resize", "app": "TestApp"])
        XCTAssertEqual(result, "错误：请提供 app、width、height 参数")
    }

    /// resize 只提供 app 和 width 缺少 height 应返回错误
    func testExecuteResizeMissingHeight() async throws {
        let result = try await tool.execute(arguments: ["action": "resize", "app": "TestApp", "width": 800])
        XCTAssertEqual(result, "错误：请提供 app、width、height 参数")
    }

    // MARK: - minimize 错误处理

    /// minimize 缺少 app 参数应返回错误
    func testExecuteMinimizeMissingApp() async throws {
        let result = try await tool.execute(arguments: ["action": "minimize"])
        XCTAssertEqual(result, "错误：请提供 app 参数")
    }

    // MARK: - 不支持的 action

    /// 不支持的 action 应返回错误
    func testExecuteUnsupportedAction() async throws {
        let result = try await tool.execute(arguments: ["action": "unknown"])
        XCTAssertEqual(result, "错误：不支持的操作，支持 list/focus/move/resize/minimize")
    }

    /// action 不是 String 类型应返回错误
    func testExecuteActionNotString() async throws {
        let result = try await tool.execute(arguments: ["action": 123])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }
}
#endif
