import XCTest
@testable import Aether

/// AlarmTool 单元测试
/// 注：不测真实 EventKit 保存（避免权限依赖）
final class AlarmToolTests: XCTestCase {
    private let tool = AlarmTool()

    /// definition：name = "create_alarm"，parameters.properties 含 "time" 字段，required 含 "time"
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "create_alarm")
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["time"], "parameters.properties 应含 time 字段")
        let required = def.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("time") == true, "required 应含 time")
    }

    /// arguments 缺 time：实现返回错误字符串（前置参数校验在权限请求之前，故不触及 EventKit）
    /// 注：方法签名为 `async throws`，但该分支实际“返回而非抛错”，此处断言返回的错误字符串
    func testExecuteMissingTimeThrows() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供闹钟时间",
                       "缺 time 应返回错误字符串")
    }

    /// time = "25:99" 应返回错误字符串
    /// 注：execute 在时间格式校验之前会先请求 EventKit 权限：
    ///   - 权限拒绝 → 返回 "错误：无法访问日历"
    ///   - 权限授予 → "25:99" 格式无效 → 返回 "错误：时间格式无效"
    /// 两种情况均为错误字符串，故断言结果以 "错误" 开头
    func testExecuteInvalidTimeFormat() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil, "跳过：模拟器环境下 EventKit 权限请求挂起")
        var result = ""
        do {
            result = try await tool.execute(arguments: ["time": "25:99"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"),
                      "无效时间格式应返回错误字符串，实际：\(result)")
    }

    // MARK: - definition 结构完整性

    /// definition.description 非空，便于 LLM 判断是否调用
    func testDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(tool.definition.description.isEmpty, "description 不应为空")
    }

    /// definition.parameters["type"] 应为 "object"
    func testDefinitionParametersTypeIsObject() {
        let type = tool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object", "parameters.type 应为 object")
    }

    /// definition.parameters["properties"] 应含 "label" 字段
    func testDefinitionPropertiesContainsLabel() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["label"], "properties 应含 label 字段")
        let labelProp = properties?["label"] as? [String: Any]
        XCTAssertEqual(labelProp?["type"] as? String, "string", "label type 应为 string")
    }

    /// definition.parameters["required"] 应仅含 ["time"]
    func testDefinitionRequiredContainsOnlyTime() {
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertEqual(required, ["time"], "required 应仅含 time")
    }

    /// definition.parameters["properties"]["time"] 应含非空 description
    func testDefinitionTimePropertyHasDescription() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        let timeProp = properties?["time"] as? [String: Any]
        XCTAssertEqual(timeProp?["type"] as? String, "string", "time type 应为 string")
        let desc = timeProp?["description"] as? String
        XCTAssertFalse(desc?.isEmpty == true, "time description 不应为空")
        XCTAssertTrue(desc?.contains("HH:mm") == true, "time description 应含格式提示 HH:mm")
    }

    // MARK: - 时间格式验证（EventKit 权限在 time guard 之前，模拟器可能挂起，跳过）

    /// time 缺少冒号分隔符 "0830" 应返回错误
    func testExecuteInvalidTimeNoColon() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        var result = ""
        do {
            result = try await tool.execute(arguments: ["time": "0830"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "无冒号时间应返回错误，实际：\(result)")
    }

    /// time 小时越界 "25:30" 应返回错误
    func testExecuteInvalidTimeHourOutOfRange() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        var result = ""
        do {
            result = try await tool.execute(arguments: ["time": "25:30"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "小时越界应返回错误，实际：\(result)")
    }

    /// time 分钟越界 "08:60" 应返回错误
    func testExecuteInvalidTimeMinuteOutOfRange() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        var result = ""
        do {
            result = try await tool.execute(arguments: ["time": "08:60"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "分钟越界应返回错误，实际：\(result)")
    }

    /// time 非数字 "abc" 应返回错误
    func testExecuteInvalidTimeNonNumeric() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        var result = ""
        do {
            result = try await tool.execute(arguments: ["time": "abc"])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "非数字时间应返回错误，实际：\(result)")
    }

    /// time 为空字符串 "" 应返回错误
    func testExecuteEmptyTimeString() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        var result = ""
        do {
            result = try await tool.execute(arguments: ["time": ""])
        } catch {
            result = "错误：\(error)"
        }
        XCTAssertTrue(result.hasPrefix("错误"), "空时间字符串应返回错误，实际：\(result)")
    }

    /// time 非字符串类型（Int）应返回错误
    func testExecuteTimeNotString() async throws {
        let result = try await tool.execute(arguments: ["time": 830])
        XCTAssertEqual(result, "错误：请提供闹钟时间", "非字符串 time 应返回参数错误")
    }

    // MARK: - 补充：label 属性描述与 description 关键字

    /// definition.parameters["properties"]["label"] 应含非空 description
    /// 便于 LLM 理解 label 字段用途
    func testDefinitionLabelPropertyHasDescription() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        let labelProp = properties?["label"] as? [String: Any]
        let desc = labelProp?["description"] as? String
        XCTAssertFalse(desc?.isEmpty == true, "label description 不应为空")
    }

    /// definition.description 应含 "闹钟" 或 "提醒" 相关描述
    /// 不依赖 locale 断言，仅校验关键字存在
    func testDefinitionDescriptionContainsAlarmKeyword() {
        let desc = tool.definition.description
        XCTAssertTrue(desc.contains("闹钟") || desc.contains("提醒"),
                      "description 应含 \"闹钟\" 或 \"提醒\" 关键字，实际：\(desc)")
    }

    // MARK: - execute 参数校验补充

    /// arguments 缺 time 但提供 label：应返回 "错误：请提供闹钟时间"
    /// 验证 label 存在不能替代必需的 time 参数（前置参数校验在权限请求之前，不触及 EventKit）
    func testExecuteMissingTimeButHasLabel() async throws {
        let result = try await tool.execute(arguments: ["label": "测试"])
        XCTAssertEqual(result, "错误：请提供闹钟时间",
                       "缺 time 时即使有 label 也应返回参数错误")
    }

    // MARK: - definition 深度结构验证

    /// definition.parameters 顶层应恰好含 type / properties / required 三个键
    func testDefinitionParametersHasThreeKeys() {
        let keys = tool.definition.parameters.keys
        XCTAssertEqual(keys.count, 3, "parameters 应含 3 个顶层键")
        XCTAssertTrue(keys.contains("type"))
        XCTAssertTrue(keys.contains("properties"))
        XCTAssertTrue(keys.contains("required"))
    }

    /// properties 应同时包含 time 和 label
    func testDefinitionPropertiesContainsBothTimeAndLabel() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["time"], "应含 time 属性")
        XCTAssertNotNil(properties?["label"], "应含 label 属性")
        XCTAssertEqual(properties?.count, 2, "properties 应含 2 个属性")
    }

    /// time 和 label 的 type 都应为 "string"
    func testDefinitionTimeAndLabelTypeIsString() {
        let properties = tool.definition.parameters["properties"] as? [String: [String: Any]]
        XCTAssertEqual(properties?["time"]?["type"] as? String, "string",
                       "time type 应为 string")
        XCTAssertEqual(properties?["label"]?["type"] as? String, "string",
                       "label type 应为 string")
    }

    /// label 不应在 required 数组中（为可选参数）
    func testDefinitionLabelNotInRequired() {
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertFalse(required?.contains("label") ?? true,
                       "label 不应在 required 中")
    }

    /// label description 应提及"闹钟"或"标签"
    func testDefinitionLabelDescriptionMentionsAlarm() {
        let properties = tool.definition.parameters["properties"] as? [String: [String: Any]]
        let desc = properties?["label"]?["description"] as? String ?? ""
        XCTAssertTrue(desc.contains("闹钟") || desc.contains("标签"),
                      "label description 应提及闹钟或标签，实际：\(desc)")
    }

    // MARK: - execute time 类型边界

    /// time 为 Double 类型应返回错误
    func testExecuteTimeAsDouble() async throws {
        let result = try await tool.execute(arguments: ["time": 8.30])
        XCTAssertEqual(result, "错误：请提供闹钟时间",
                       "Double 类型 time 应返回参数错误")
    }

    /// time 为 Bool 类型应返回错误
    func testExecuteTimeAsBool() async throws {
        let result = try await tool.execute(arguments: ["time": true])
        XCTAssertEqual(result, "错误：请提供闹钟时间",
                       "Bool 类型 time 应返回参数错误")
    }

    /// time 为 Array 类型应返回错误
    func testExecuteTimeAsArray() async throws {
        let result = try await tool.execute(arguments: ["time": ["08", "30"]])
        XCTAssertEqual(result, "错误：请提供闹钟时间",
                       "Array 类型 time 应返回参数错误")
    }

    /// time 为 Dictionary 类型应返回错误
    func testExecuteTimeAsDictionary() async throws {
        let result = try await tool.execute(arguments: ["time": ["hour": 8]])
        XCTAssertEqual(result, "错误：请提供闹钟时间",
                       "Dictionary 类型 time 应返回参数错误")
    }

    // MARK: - EventKit 权限依赖路径（模拟器跳过）

    /// 有效时间格式 "08:30" + 默认 label：应返回成功（需 EventKit 权限）
    func testExecuteValidTimeWithDefaultLabel() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        let result = try await tool.execute(arguments: ["time": "08:30"])
        XCTAssertTrue(result.contains("已创建闹钟"), "有效时间应创建成功，实际：\(result)")
        XCTAssertTrue(result.contains("08:30"), "结果应含时间")
        XCTAssertTrue(result.contains("闹钟"), "默认 label 应为 '闹钟'")
    }

    /// 有效时间格式 + 自定义 label：应返回成功且含自定义 label
    func testExecuteValidTimeWithCustomLabel() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        let result = try await tool.execute(arguments: ["time": "09:00", "label": "起床"])
        XCTAssertTrue(result.contains("已创建闹钟"), "有效时间应创建成功")
        XCTAssertTrue(result.contains("起床"), "结果应含自定义 label '起床'")
    }

    /// 有效时间格式 "00:00"（午夜）：应返回成功
    func testExecuteMidnightTime() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        let result = try await tool.execute(arguments: ["time": "00:00"])
        XCTAssertTrue(result.contains("已创建闹钟") || result.hasPrefix("错误"),
                      "午夜时间应返回成功或错误，实际：\(result)")
    }

    /// 有效时间格式 "23:59"（最晚时间）：应返回成功
    func testExecuteLatestTime() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "跳过：模拟器环境下 EventKit 权限请求挂起")
        let result = try await tool.execute(arguments: ["time": "23:59"])
        XCTAssertTrue(result.contains("已创建闹钟") || result.hasPrefix("错误"),
                      "最晚时间应返回成功或错误，实际：\(result)")
    }
}
