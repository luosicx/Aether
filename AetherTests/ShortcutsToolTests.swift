import XCTest
@testable import Aether

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

    // MARK: - RunShortcutTool definition 详细验证

    /// run_shortcut 的 properties 应包含 name 和 input
    func testRunDefinitionProperties() {
        let properties = runTool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertNotNil(properties, "properties 应为字典")
        XCTAssertNotNil(properties?["name"], "应包含 name 属性")
        XCTAssertNotNil(properties?["input"], "应包含 input 属性")
        XCTAssertEqual(properties?["name"]?["type"] as? String, "string")
        XCTAssertEqual(properties?["input"]?["type"] as? String, "string")
    }

    /// run_shortcut 的 type 应为 object
    func testRunDefinitionType() {
        let type = runTool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object")
    }

    // MARK: - RunShortcutTool execute 错误路径

    /// 缺少 name 参数应返回错误
    func testRunExecuteMissingName() async throws {
        let result = try await runTool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供快捷指令名称")
    }

    /// name 为空字符串应返回错误
    func testRunExecuteEmptyName() async throws {
        let result = try await runTool.execute(arguments: ["name": ""])
        XCTAssertEqual(result, "错误：请提供快捷指令名称")
    }

    #if os(iOS)
    /// iOS 下提供 name 应返回触发成功消息
    func testRunExecuteWithNameOnIOS() async throws {
        let result = try await runTool.execute(arguments: ["name": "TestShortcut"])
        XCTAssertEqual(result, "已触发快捷指令：TestShortcut")
    }

    /// iOS 下提供 name 和 input 应返回触发成功消息
    func testRunExecuteWithNameAndInputOnIOS() async throws {
        let result = try await runTool.execute(arguments: ["name": "TestShortcut", "input": "hello"])
        XCTAssertEqual(result, "已触发快捷指令：TestShortcut")
    }
    #endif

    // MARK: - ListShortcutsTool definition 详细验证

    /// list_shortcuts 的 required 应为空数组
    func testListDefinitionRequiredEmpty() {
        let required = listTool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, [], "list_shortcuts 不应有必填参数")
    }

    /// list_shortcuts 的 type 应为 object
    func testListDefinitionType() {
        let type = listTool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object")
    }

    #if os(iOS)
    /// iOS 下列出快捷指令应返回不支持提示
    func testListExecuteReturnsIOSMessage() async throws {
        let result = try await listTool.execute(arguments: [:])
        XCTAssertEqual(result, "iOS 不支持列出快捷指令，请在快捷指令 App 中查看")
    }
    #endif

    // MARK: - CreateShortcutTool definition 详细验证

    /// create_shortcut 的 properties 应包含 name/action/url/script/text
    func testCreateDefinitionProperties() {
        let properties = createTool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertNotNil(properties, "properties 应为字典")
        XCTAssertNotNil(properties?["name"], "应包含 name 属性")
        XCTAssertNotNil(properties?["action"], "应包含 action 属性")
        XCTAssertNotNil(properties?["url"], "应包含 url 属性")
        XCTAssertNotNil(properties?["script"], "应包含 script 属性")
        XCTAssertNotNil(properties?["text"], "应包含 text 属性")
    }

    /// create_shortcut 的 type 应为 object
    func testCreateDefinitionType() {
        let type = createTool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object")
    }

    // MARK: - CreateShortcutTool execute 缺参数错误

    /// open_url 动作缺 url 参数 → buildWorkflowAction 返回 nil → 不支持动作错误
    func testCreateOpenUrlWithoutUrl() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "open_url"])
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/run_script/show_text/copy_to_clipboard")
    }

    /// run_script 动作缺 script 参数
    func testCreateRunScriptWithoutScript() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "run_script"])
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/run_script/show_text/copy_to_clipboard")
    }

    /// show_text 动作缺 text 参数
    func testCreateShowTextWithoutText() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "show_text"])
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/run_script/show_text/copy_to_clipboard")
    }

    /// copy_to_clipboard 动作缺 text 参数
    func testCreateCopyToClipboardWithoutText() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "copy_to_clipboard"])
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/run_script/show_text/copy_to_clipboard")
    }

    /// name 为空字符串应返回错误
    func testCreateEmptyName() async throws {
        let result = try await createTool.execute(arguments: ["name": "", "action": "open_url"])
        XCTAssertEqual(result, "错误：请提供快捷指令名称")
    }
}
