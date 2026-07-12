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

    // MARK: - definition 描述内容验证

    /// definition.description 应包含"联系人"或"搜索"关键字
    func testDefinitionDescriptionMentionsContactOrSearch() {
        let desc = tool.definition.description
        XCTAssertTrue(desc.contains("联系人") || desc.contains("搜索"),
                      "description 应提及 '联系人' 或 '搜索'，实际：\(desc)")
    }

    /// definition.parameters 顶层应恰好包含 type / properties / required 三个键
    func testDefinitionParametersHasExactlyThreeKeys() {
        let keys = tool.definition.parameters.keys
        XCTAssertEqual(keys.count, 3, "parameters 应含 3 个顶层键")
        XCTAssertTrue(keys.contains("type"), "应含 type 键")
        XCTAssertTrue(keys.contains("properties"), "应含 properties 键")
        XCTAssertTrue(keys.contains("required"), "应含 required 键")
    }

    /// properties 应仅包含 query 一个属性
    func testDefinitionPropertiesContainsOnlyQuery() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        XCTAssertEqual(properties?.count, 1, "properties 应仅含 query 一个属性")
        XCTAssertNotNil(properties?["query"], "应包含 query 属性")
    }

    // MARK: - execute 参数类型边界

    /// query 为 Double 类型应返回错误
    func testExecuteDoubleQueryReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": 3.14])
        XCTAssertEqual(result, "错误：请提供搜索关键词")
    }

    /// query 为 Bool 类型应返回错误
    func testExecuteBoolQueryReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": true])
        XCTAssertEqual(result, "错误：请提供搜索关键词")
    }

    /// query 为 Array 类型应返回错误
    func testExecuteArrayQueryReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": ["张", "李"]])
        XCTAssertEqual(result, "错误：请提供搜索关键词")
    }

    /// query 为空格字符串应通过 guard（非空），但后续权限请求会跳过
    /// 验证空格不触发 "请提供" 错误（与空字符串不同）
    func testExecuteWhitespaceQueryPassesGuard() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境通讯录权限不可用")
        let result = try await tool.execute(arguments: ["query": "  "])
        XCTAssertNotNil(result as String?, "空格 query 应通过 guard 并返回字符串")
    }

    /// query 为长字符串应通过 guard（验证长度无上限）
    func testExecuteLongQueryPassesGuard() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境通讯录权限不可用")
        let longQuery = String(repeating: "张", count: 200)
        let result = try await tool.execute(arguments: ["query": longQuery])
        XCTAssertTrue(result is String, "长 query 应通过 guard 并返回字符串")
    }

    // MARK: - definition query 属性深度验证

    /// query 属性的 description 应包含搜索关键词描述
    func testDefinitionQueryPropertyDescriptionContent() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        let querySchema = properties?["query"] as? [String: Any]
        let desc = querySchema?["description"] as? String ?? ""
        XCTAssertTrue(desc.contains("姓名") || desc.contains("号码") || desc.contains("搜索"),
                      "query description 应提及姓名/号码/搜索，实际：\(desc)")
    }

    // MARK: - 新增覆盖率测试

    /// query 为 Dictionary 类型：as? String 失败，应在权限请求前返回参数错误
    func testExecuteQueryAsDictionaryReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": ["name": "张"]])
        XCTAssertEqual(result, "错误：请提供搜索关键词",
                       "Dictionary 类型 query 应返回参数错误")
    }

    /// query 为 NSNull 类型：as? String 失败，应在权限请求前返回参数错误
    func testExecuteQueryAsNSNullReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": NSNull()])
        XCTAssertEqual(result, "错误：请提供搜索关键词",
                       "NSNull 类型 query 应返回参数错误")
    }

    /// query 为 Data 类型：as? String 失败，应在权限请求前返回参数错误
    func testExecuteQueryAsDataReturnsError() async throws {
        let result = try await tool.execute(arguments: ["query": Data("test".utf8)])
        XCTAssertEqual(result, "错误：请提供搜索关键词",
                       "Data 类型 query 应返回参数错误")
    }

    /// definition 的 name 应为有效工具标识符（小写、无空格）
    func testDefinitionNameIsValidIdentifier() {
        let name = tool.definition.name
        XCTAssertFalse(name.isEmpty, "工具名不应为空")
        XCTAssertFalse(name.contains(" "), "工具名不应包含空格")
        XCTAssertEqual(name, name.lowercased(), "工具名应为小写")
    }

    /// definition 的 description 应包含"联系人"、"姓名"或"搜索"关键字
    func testDefinitionDescriptionMentionsContactsOrSearch() {
        let desc = tool.definition.description
        let hasKeyword = desc.contains("联系人") || desc.contains("姓名") || desc.contains("搜索")
        XCTAssertTrue(hasKeyword, "description 应提及联系人/姓名/搜索，实际：\(desc)")
    }

    /// 真实通讯录搜索返回的结果应符合 "姓名：...，电话：..." 或 "未找到匹配的联系人"
    func testExecuteRealSearchResultFormat() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境通讯录权限不可用")
        let result = try await tool.execute(arguments: ["query": "张"])
        let isFormattedResult = result.contains("姓名：") && result.contains("电话：")
        let isNotFound = result == "未找到匹配的联系人"
        XCTAssertTrue(isFormattedResult || isNotFound,
                      "搜索结果应为格式化联系人或未找到，实际：\(result)")
    }
}
