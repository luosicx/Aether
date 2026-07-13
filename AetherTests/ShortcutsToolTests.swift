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
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/show_text/copy_to_clipboard")
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

    /// create_shortcut 的 properties 应包含 name/action/url/text（run_script 已移除，不再含 script）
    func testCreateDefinitionProperties() {
        let properties = createTool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertNotNil(properties, "properties 应为字典")
        XCTAssertNotNil(properties?["name"], "应包含 name 属性")
        XCTAssertNotNil(properties?["action"], "应包含 action 属性")
        XCTAssertNotNil(properties?["url"], "应包含 url 属性")
        XCTAssertNil(properties?["script"], "run_script 已移除，不应再包含 script 属性")
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
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/show_text/copy_to_clipboard")
    }

    /// run_script 动作已被移除
    func testCreateRunScriptIsRejected() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "run_script"])
        XCTAssertEqual(result, "该 action 已被移除")
    }

    /// show_text 动作缺 text 参数
    func testCreateShowTextWithoutText() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "show_text"])
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/show_text/copy_to_clipboard")
    }

    /// copy_to_clipboard 动作缺 text 参数
    func testCreateCopyToClipboardWithoutText() async throws {
        let result = try await createTool.execute(arguments: ["name": "test", "action": "copy_to_clipboard"])
        XCTAssertEqual(result, "错误：不支持的动作类型，支持 open_url/show_text/copy_to_clipboard")
    }

    /// name 为空字符串应返回错误
    func testCreateEmptyName() async throws {
        let result = try await createTool.execute(arguments: ["name": "", "action": "open_url"])
        XCTAssertEqual(result, "错误：请提供快捷指令名称")
    }

    // MARK: - definition 描述验证

    /// run_shortcut 的 description 不应为空
    func testRunDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(runTool.definition.description.isEmpty,
                       "run_shortcut description 不应为空")
    }

    /// list_shortcuts 的 description 不应为空
    func testListDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(listTool.definition.description.isEmpty,
                       "list_shortcuts description 不应为空")
    }

    /// create_shortcut 的 description 不应为空
    func testCreateDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(createTool.definition.description.isEmpty,
                       "create_shortcut description 不应为空")
    }

    /// create_shortcut description 应提及动作类型
    func testCreateDefinitionDescriptionMentionsActions() {
        let desc = createTool.definition.description
        XCTAssertTrue(desc.contains("open_url") || desc.contains("show_text") || desc.contains("copy_to_clipboard"),
                      "description 应提及动作类型，实际：\(desc)")
    }

    /// run_shortcut description 应提及快捷指令
    func testRunDefinitionDescriptionMentionsShortcut() {
        let desc = runTool.definition.description
        XCTAssertTrue(desc.contains("快捷指令"),
                      "description 应提及 '快捷指令'，实际：\(desc)")
    }

    // MARK: - definition 结构补充验证

    /// list_shortcut 的 properties 应为空字典
    func testListDefinitionPropertiesEmpty() {
        let properties = listTool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties, "properties 应存在")
        XCTAssertEqual(properties?.count, 0, "list_shortcut 的 properties 应为空字典")
    }

    /// run_shortcut 的 required 应仅包含 name
    func testRunDefinitionRequiredOnlyName() {
        let required = runTool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["name"], "required 应仅含 name")
    }

    /// create_shortcut 的 name 属性应有 description
    func testCreateDefinitionNamePropertyHasDescription() {
        let properties = createTool.definition.parameters["properties"] as? [String: [String: Any]]
        let nameProp = properties?["name"]
        XCTAssertNotNil(nameProp?["description"] as? String,
                        "name 属性应有 description")
        XCTAssertFalse((nameProp?["description"] as? String)?.isEmpty ?? true,
                       "name description 不应为空")
    }

    /// create_shortcut 的 action 属性应有 description 且提及动作类型
    func testCreateDefinitionActionPropertyDescription() {
        let properties = createTool.definition.parameters["properties"] as? [String: [String: Any]]
        let actionProp = properties?["action"]
        let desc = actionProp?["description"] as? String ?? ""
        XCTAssertFalse(desc.isEmpty, "action description 不应为空")
        XCTAssertTrue(desc.contains("open_url") || desc.contains("show_text") || desc.contains("copy_to_clipboard"),
                      "action description 应提及动作类型")
    }

    // MARK: - execute 参数类型校验

    /// name 为非 String 类型（Int）应返回错误
    func testRunExecuteNameNotString() async throws {
        let result = try await runTool.execute(arguments: ["name": 123])
        XCTAssertEqual(result, "错误：请提供快捷指令名称")
    }

    /// name 为非 String 类型（Int）应返回错误
    func testCreateExecuteNameNotString() async throws {
        let result = try await createTool.execute(arguments: ["name": 123, "action": "open_url"])
        XCTAssertEqual(result, "错误：请提供快捷指令名称")
    }

    // MARK: - CreateShortcutTool 各 action 成功路径

    /// open_url 动作成功路径：应返回创建成功消息
    func testCreateOpenUrlSuccess() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：CI 环境下 UIApplication.shared.open 可能不可用")
        let result = try await createTool.execute(arguments: [
            "name": "TestOpenURL",
            "action": "open_url",
            "url": "https://example.com"
        ])
        XCTAssertTrue(result.contains("已创建快捷指令"), "open_url 成功应返回创建消息，实际：\(result)")
        XCTAssertTrue(result.contains("TestOpenURL"))
    }

    /// run_script 动作成功路径：应被移除并拒绝
    func testCreateRunScriptSuccessIsRejected() async throws {
        let result = try await createTool.execute(arguments: [
            "name": "TestRunScript",
            "action": "run_script",
            "script": "echo hello"
        ])
        XCTAssertEqual(result, "该 action 已被移除", "run_script 应已被移除，实际：\(result)")
    }

    /// show_text 动作成功路径：应返回创建成功消息
    func testCreateShowTextSuccess() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：CI 环境下 UIApplication.shared.open 可能不可用")
        let result = try await createTool.execute(arguments: [
            "name": "TestShowText",
            "action": "show_text",
            "text": "Hello World"
        ])
        XCTAssertTrue(result.contains("已创建快捷指令"), "show_text 成功应返回创建消息，实际：\(result)")
    }

    /// copy_to_clipboard 动作成功路径：应返回创建成功消息
    func testCreateCopyToClipboardSuccess() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：CI 环境下 UIApplication.shared.open 可能不可用")
        let result = try await createTool.execute(arguments: [
            "name": "TestCopy",
            "action": "copy_to_clipboard",
            "text": "clipboard content"
        ])
        XCTAssertTrue(result.contains("已创建快捷指令"), "copy_to_clipboard 成功应返回创建消息，实际：\(result)")
    }
}
