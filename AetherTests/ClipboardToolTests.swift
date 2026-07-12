import XCTest
@testable import Aether

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
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：UIPasteboard 在模拟器/CI 环境行为不稳定")
        _ = try await writeTool.execute(arguments: ["text": "test123"])
        let result = try await readTool.execute(arguments: [:])
        XCTAssertEqual(result, "test123")
    }

    func testWriteMissingText() async throws {
        let result = try await writeTool.execute(arguments: [:])
        XCTAssertTrue(result.hasPrefix("错误"))
    }

    // MARK: - definition 完整性验证

    /// read_clipboard description 不应为空
    func testReadDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(readTool.definition.description.isEmpty,
                       "read_clipboard description 不应为空")
    }

    /// write_clipboard description 不应为空
    func testWriteDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(writeTool.definition.description.isEmpty,
                       "write_clipboard description 不应为空")
    }

    /// read_clipboard 的 type 应为 "object"
    func testReadDefinitionTypeIsObject() {
        let type = readTool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object", "type 应为 object")
    }

    /// write_clipboard 的 type 应为 "object"
    func testWriteDefinitionTypeIsObject() {
        let type = writeTool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object", "type 应为 object")
    }

    /// read_clipboard 的 properties 应为空字典
    func testReadDefinitionPropertiesEmpty() {
        let properties = readTool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties, "properties 应存在")
        XCTAssertEqual(properties?.count, 0, "read_clipboard 的 properties 应为空")
    }

    /// read_clipboard 的 required 应为空数组
    func testReadDefinitionRequiredEmpty() {
        let required = readTool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, [], "read_clipboard 的 required 应为空数组")
    }

    /// read_clipboard parameters 顶层应含 3 个键
    func testReadDefinitionParametersHasThreeKeys() {
        let keys = readTool.definition.parameters.keys
        XCTAssertEqual(keys.count, 3, "parameters 应含 3 个顶层键")
        XCTAssertTrue(keys.contains("type"))
        XCTAssertTrue(keys.contains("properties"))
        XCTAssertTrue(keys.contains("required"))
    }

    /// write_clipboard parameters 顶层应含 3 个键
    func testWriteDefinitionParametersHasThreeKeys() {
        let keys = writeTool.definition.parameters.keys
        XCTAssertEqual(keys.count, 3, "parameters 应含 3 个顶层键")
        XCTAssertTrue(keys.contains("type"))
        XCTAssertTrue(keys.contains("properties"))
        XCTAssertTrue(keys.contains("required"))
    }

    /// write_clipboard 的 text 属性应有 type 和 description
    func testWriteDefinitionTextPropertyStructure() {
        let properties = writeTool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertNotNil(properties?["text"], "应含 text 属性")
        XCTAssertEqual(properties?["text"]?["type"] as? String, "string",
                       "text type 应为 string")
        let desc = properties?["text"]?["description"] as? String
        XCTAssertFalse(desc?.isEmpty ?? true, "text description 不应为空")
    }

    /// write_clipboard 的 required 应仅含 text
    func testWriteDefinitionRequiredOnlyText() {
        let required = writeTool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["text"], "required 应仅含 text")
    }

    // MARK: - write 错误边界

    /// text 为空字符串应返回错误
    func testWriteEmptyTextReturnsError() async throws {
        let result = try await writeTool.execute(arguments: ["text": ""])
        XCTAssertEqual(result, "错误：请提供要写入的文本",
                       "空 text 应返回错误")
    }

    /// text 为非 String 类型（Int）应返回错误
    func testWriteTextNotStringReturnsError() async throws {
        let result = try await writeTool.execute(arguments: ["text": 123])
        XCTAssertEqual(result, "错误：请提供要写入的文本",
                       "非 String 类型 text 应返回错误")
    }

    /// text 为 Bool 类型应返回错误
    func testWriteTextBoolReturnsError() async throws {
        let result = try await writeTool.execute(arguments: ["text": true])
        XCTAssertEqual(result, "错误：请提供要写入的文本",
                       "Bool 类型 text 应返回错误")
    }

    // MARK: - read 边界

    /// read 应始终返回非空字符串（空剪贴板时返回 "剪贴板为空"）
    func testReadAlwaysReturnsNonEmptyString() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：CI 环境下 UIPasteboard 行为不稳定")
        let result = try await readTool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "read 应始终返回非空字符串")
    }

    /// read 多次调用应返回一致结果（无写入时）
    func testReadMultipleCallsConsistent() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：CI 环境下 UIPasteboard 行为不稳定")
        let result1 = try await readTool.execute(arguments: [:])
        let result2 = try await readTool.execute(arguments: [:])
        XCTAssertEqual(result1, result2, "无写入时多次读取应返回一致结果")
    }
}
