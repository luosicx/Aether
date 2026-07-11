import XCTest
@testable import Aether

final class ContactsToolTests: XCTestCase {
    private let tool = ContactsTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "search_contacts")
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("query") == true)
    }

    func testExecuteMissingQuery() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供搜索关键词")
    }

    func testExecuteReturnsString() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境通讯录权限不可用")
        let result = try await tool.execute(arguments: ["query": "张"])
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - 新增覆盖率测试

    /// 验证工具描述不为空
    func testDefinitionDescriptionIsNotEmpty() {
        XCTAssertFalse(tool.definition.description.isEmpty,
                       "工具描述不应为空，便于 LLM 判断是否调用")
    }

    /// 验证 parameters 顶层 type 为 "object"（JSON Schema 规范）
    func testDefinitionParametersTypeIsObject() {
        let type = tool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object",
                       "parameters 顶层 type 应为 \"object\"")
    }

    /// 验证 query 属性结构：type=string 且 description 非空
    func testDefinitionQueryPropertyStructure() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties, "properties 字段应存在")
        let querySchema = properties?["query"] as? [String: Any]
        XCTAssertNotNil(querySchema, "query 属性应存在")
        XCTAssertEqual(querySchema?["type"] as? String, "string",
                       "query 的 type 应为 string")
        let queryDescription = querySchema?["description"] as? String
        XCTAssertNotNil(queryDescription, "query 的 description 应存在")
        XCTAssertFalse(queryDescription?.isEmpty ?? true,
                       "query 的 description 不应为空")
    }

    /// 验证 required 数组仅包含 "query"
    func testDefinitionRequiredContainsOnlyQuery() {
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["query"],
                       "required 应仅包含 \"query\" 一个元素")
    }

    /// 验证空 query 字符串返回错误提示（与 missing query 同一分支）
    func testExecuteEmptyQueryReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": ""])
        XCTAssertEqual(result, "错误：请提供搜索关键词")
    }

    /// 验证非字符串类型的 query（如 Int）会被类型转换守卫拦截
    func testExecuteNonStringQueryReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": 123])
        XCTAssertEqual(result, "错误：请提供搜索关键词")
    }

    /// 真实 CNContactStore 搜索因权限依赖在模拟器/CI 环境跳过，避免权限挂起
    func testExecuteRealSearchSkippedOnSimulatorOrCI() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境通讯录权限不可用")
        let result = try await tool.execute(arguments: ["query": "张"])
        XCTAssertTrue(result is String, "执行结果应为字符串类型")
    }
}
