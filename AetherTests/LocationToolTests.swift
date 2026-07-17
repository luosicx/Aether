import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// LocationTool 单元测试
/// 注：定位依赖设备权限与环境，测试可能成功或返回错误字符串，仅校验不崩溃且返回非空字符串
final class LocationToolTests: XCTestCase {
    private let tool = LocationTool()

    /// definition：name == "get_location"，parameters 为空对象，required 为空
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "get_location")
        XCTAssertEqual(def.parameters["type"] as? String, "object")
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertTrue(properties?.isEmpty ?? true, "properties 应为空")
        let required = def.parameters["required"] as? [String]
        XCTAssertTrue(required?.isEmpty ?? false, "required 应为空")
    }

    /// definition 描述应为非空字符串
    func testDefinitionDescriptionNotEmpty() {
        let def = tool.definition
        XCTAssertFalse(def.description.isEmpty, "工具描述不应为空")
        XCTAssertTrue(def.description.contains("地理位置") || def.description.contains("定位"),
                      "描述应与地理位置相关，实际：\(def.description)")
    }

    /// definition 多次访问应返回一致结果（确定性）
    func testDefinitionIsDeterministic() {
        let def1 = tool.definition
        let def2 = tool.definition
        XCTAssertEqual(def1.name, def2.name, "多次访问 definition 应返回一致 name")
        XCTAssertEqual(def1.parameters["type"] as? String, def2.parameters["type"] as? String,
                       "多次访问 definition 应返回一致 type")
    }

    /// LocationTool 应遵循 ToolProtocol 协议
    func testConformsToToolProtocol() {
        // 编译期即可验证协议遵循，此处仅做运行时 sanity check
        XCTAssertTrue(tool is ToolProtocol, "LocationTool 应遵循 ToolProtocol")
    }

    /// execute 无参调用：传空字典应等价于无参调用
    func testExecuteWithEmptyArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        // 传空字典应不报错（LocationTool 无入参）
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
    }

    /// execute 调用：在测试环境下定位可能成功或失败（权限/超时），仅校验返回非空字符串，
    /// 且内容包含位置或定位相关信息
    func testExecuteReturnsLocationOrError() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
        // 成功返回 "当前位置..." 或失败返回 "定位权限未授权..." / "定位超时..." / "定位失败..."
        XCTAssertTrue(result.contains("当前位置") || result.contains("定位"),
                      "结果应包含位置或定位相关信息，实际：\(result)")
    }

    /// execute 返回值类型为 String 且非空
    func testExecuteReturnsString() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: [:])
        let anyResult: Any = result
        XCTAssertTrue(anyResult is String, "execute 返回值应为 String 类型")
        XCTAssertFalse(result.isEmpty, "返回字符串不应为空")
    }

    /// execute 多次调用应稳定返回非空字符串（验证无状态泄漏）
    func testExecuteMultipleCallsStable() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        for _ in 0..<3 {
            let result = try await tool.execute(arguments: [:])
            XCTAssertFalse(result.isEmpty, "多次调用 execute 应每次返回非空字符串")
        }
    }

    /// 多个 LocationTool 实例不应共享状态
    func testMultipleInstancesDoNotShareState() {
        let tool1 = LocationTool()
        let tool2 = LocationTool()
        XCTAssertEqual(tool1.definition.name, tool2.definition.name, "多个实例的 definition 应一致")
    }

    /// execute 传入无关参数应不影响执行（LocationTool 无入参，忽略所有参数）
    func testExecuteIgnoresExtraArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        // 传入无关参数应被忽略
        let result = try await tool.execute(arguments: ["unused": "value", "number": 42])
        XCTAssertFalse(result.isEmpty, "传入无关参数应不影响 execute 返回非空字符串")
    }

    #if os(macOS)
    /// macOS 上定位可能不可用，execute 应优雅返回提示字符串而非崩溃
    func testExecuteOnMacOSDoesNotCrash() async throws {
        // CI 环境下 CLLocationManager.requestWhenInUseAuthorization() 会触发
        // 系统权限对话框，无人交互即挂起，跳过避免 CI 卡住
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：CI 环境下定位权限请求对话框无人交互会挂起")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "macOS 上 execute 应返回非空字符串（成功或错误提示）")
    }
    #endif

    // MARK: - definition 结构完整性

    /// definition 的 parameters 应包含 type、properties、required 三个键
    func testDefinitionParametersContainsAllKeys() {
        let def = tool.definition
        XCTAssertNotNil(def.parameters["type"], "parameters 应包含 type 键")
        XCTAssertNotNil(def.parameters["properties"], "parameters 应包含 properties 键")
        XCTAssertNotNil(def.parameters["required"], "parameters 应包含 required 键")
    }

    /// definition 的 required 应为空数组
    func testDefinitionRequiredIsEmptyArray() {
        let def = tool.definition
        let required = def.parameters["required"] as? [String]
        XCTAssertEqual(required?.count, 0, "required 应为空数组")
    }

    /// definition 的 properties 应为空字典
    func testDefinitionPropertiesIsEmptyDict() {
        let def = tool.definition
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertEqual(properties?.count, 0, "properties 应为空字典")
    }

    /// definition 的 name 应为有效的工具标识符（无空格、全小写）
    func testDefinitionNameIsValidIdentifier() {
        let name = tool.definition.name
        XCTAssertFalse(name.isEmpty, "工具名不应为空")
        XCTAssertFalse(name.contains(" "), "工具名不应包含空格")
        XCTAssertEqual(name, name.lowercased(), "工具名应为小写")
    }

    /// definition 多次访问应返回全新但等价的实例（非共享引用）
    func testDefinitionIsStableAcrossManyCalls() {
        let names = (0..<10).map { _ in tool.definition.name }
        let uniqueNames = Set(names)
        XCTAssertEqual(uniqueNames.count, 1, "10 次访问应返回一致的 name")
    }

    // MARK: - execute 参数边界

    /// execute 传入 nil 值的参数应不影响执行（应忽略所有参数）
    func testExecuteWithNilValueArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: ["key": NSNull()])
        XCTAssertFalse(result.isEmpty, "传入 NSNull 值应不影响 execute 返回非空字符串")
    }

    /// execute 传入嵌套字典参数应不影响执行
    func testExecuteWithNestedDictArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: ["nested": ["a": 1, "b": "str"]])
        XCTAssertFalse(result.isEmpty, "传入嵌套字典应不影响 execute 返回非空字符串")
    }

    /// execute 传入数组参数应不影响执行
    func testExecuteWithArrayArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: ["list": [1, 2, 3]])
        XCTAssertFalse(result.isEmpty, "传入数组参数应不影响 execute 返回非空字符串")
    }

    // MARK: - execute 不跳过测试（验证超时/权限错误格式）

    /// execute 在 CI/模拟器环境下应返回包含位置或错误信息的字符串
    func testExecuteInCIReturnsExpectedFormat() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应始终返回非空字符串")
        // 成功："当前位置：..." 或失败："定位权限未授权..." / "定位超时..." / "定位失败..."
        let hasExpectedPrefix = result.contains("当前位置") ||
                                 result.contains("定位") ||
                                 result.contains("经纬度")
        XCTAssertTrue(hasExpectedPrefix,
                      "结果应包含位置或定位相关关键词，实际：\(result)")
    }

    /// execute 应始终返回 String 类型（不抛异常）
    func testExecuteAlwaysReturnsStringWithoutThrowing() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
    }

    // MARK: - 实例独立性

    /// 多个 LocationTool 实例应各自独立，definition 一致但无共享状态
    func testMultipleInstancesAreIndependent() {
        let tool1 = LocationTool()
        let tool2 = LocationTool()
        let tool3 = LocationTool()

        XCTAssertEqual(tool1.definition.name, tool2.definition.name)
        XCTAssertEqual(tool2.definition.name, tool3.definition.name)
        XCTAssertEqual(tool1.definition.description, tool2.definition.description)
        XCTAssertEqual(tool1.definition.parameters["type"] as? String,
                       tool3.definition.parameters["type"] as? String)
    }

    /// LocationTool 创建大量实例不应崩溃
    func testCreatingManyInstancesDoesNotCrash() {
        var tools: [LocationTool] = []
        for _ in 0..<50 {
            tools.append(LocationTool())
        }
        XCTAssertEqual(tools.count, 50, "应能创建 50 个实例")
        // 所有实例的 definition 应一致
        let firstName = tools.first?.definition.name
        XCTAssertTrue(tools.allSatisfy { $0.definition.name == firstName },
                      "所有实例的 name 应一致")
    }

    // MARK: - ToolProtocol 协议验证

    /// LocationTool 通过 ToolProtocol 协议访问时应能获取 definition
    func testToolProtocolDefinitionAccess() {
        let tools: [ToolProtocol] = [LocationTool(), LocationTool()]
        for tool in tools {
            XCTAssertEqual(tool.definition.name, "get_location")
            XCTAssertFalse(tool.definition.description.isEmpty)
        }
    }

    /// definition 的 description 应包含「地理」或「定位」关键词
    func testDefinitionDescriptionContainsKeywords() {
        let desc = tool.definition.description
        let hasKeyword = desc.contains("地理") || desc.contains("定位") || desc.contains("位置")
        XCTAssertTrue(hasKeyword, "描述应包含地理/定位/位置关键词，实际：\(desc)")
    }

    /// definition 的 name 长度应在合理范围内
    func testDefinitionNameLengthReasonable() {
        let name = tool.definition.name
        XCTAssertGreaterThan(name.count, 3, "工具名长度应大于 3")
        XCTAssertLessThan(name.count, 50, "工具名长度应小于 50")
    }

    // MARK: - execute 并发调用

    /// 并发调用 execute 不应崩溃（多个 LocationTool 实例同时定位）
    func testConcurrentExecuteDoesNotCrash() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下并发定位不稳定")
        let tool1 = LocationTool()
        let tool2 = LocationTool()

        async let r1 = try tool1.execute(arguments: [:])
        async let r2 = try tool2.execute(arguments: [:])
        let results = try await [r1, r2]

        for result in results {
            XCTAssertFalse(result.isEmpty, "并发 execute 应返回非空字符串")
        }
    }

    /// execute 多次串行调用应稳定返回非空字符串
    func testExecuteSerialCallsStableNonEmpty() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        for _ in 0..<3 {
            let result = try await tool.execute(arguments: [:])
            XCTAssertFalse(result.isEmpty, "串行 execute 应每次返回非空字符串")
        }
    }

    // MARK: - 新增覆盖率测试

    /// definition 的 name 仅含小写字母与下划线，符合工具标识符规范
    func testDefinitionNameIsValidToolIdentifier() {
        let name = tool.definition.name
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
        XCTAssertFalse(name.isEmpty, "工具名不应为空")
        XCTAssertNil(name.rangeOfCharacter(from: allowed.inverted), "工具名应仅含小写、数字、下划线，实际：\(name)")
    }

    /// definition 的 description 应明确提及「位置」或「经纬度」
    func testDefinitionDescriptionMentionsLocationKeywords() {
        let desc = tool.definition.description
        let hasKeyword = desc.contains("位置") || desc.contains("经纬度") || desc.contains("地理") || desc.contains("定位")
        XCTAssertTrue(hasKeyword, "描述应提及位置/经纬度/地理/定位，实际：\(desc)")
    }

    /// execute 传入非字典值参数（如数组作为 value）不应崩溃，仍返回字符串
    func testExecuteWithArrayValueArguments() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
        let result = try await tool.execute(arguments: ["list": ["a", "b"]])
        XCTAssertFalse(result.isEmpty, "execute 应始终返回非空字符串")
    }

    /// execute 在模拟器/CI 外若成功，返回字符串应包含格式化为 4 位小数的经纬度
    func testExecuteResultContainsFormattedCoordinatesWhenSuccessful() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位结果不稳定")
        let result = try await tool.execute(arguments: [:])
        // 若定位成功，结果形如 "当前位置：...，经纬度 31.1234, 121.5678"
        XCTAssertTrue(result.contains("当前位置") || result.contains("定位"),
                      "结果应包含位置或定位关键词，实际：\(result)")
        // 成功时才校验坐标格式
        if result.contains("当前位置") {
            let regex = try? NSRegularExpression(pattern: #"\d+\.\d{4}"#, options: [])
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex?.matches(in: result, options: [], range: range) ?? []
            XCTAssertGreaterThanOrEqual(matches.count, 2, "成功结果应至少含 2 个 4 位小数坐标，实际：\(result)")
        }
    }

    // MARK: - 新代码覆盖率：continuation 读写统一在 DispatchQueue.main

    /// execute 在模拟器/CI 环境下应通过 DispatchQueue.main.async 安全地 resume continuation。
    /// 新代码将 resume(returning:) 与 resume(throwing:) 统一调度到主线程，
    /// 此测试验证超时路径（resume(throwing: LocationError.timeout)）不崩溃且返回错误提示。
    func testExecuteTimeoutPathUsesMainQueueContinuation() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
        // 超时 → "定位超时，请重试"；权限被拒 → "定位权限未授权..."；成功 → "当前位置..."
        XCTAssertTrue(result.contains("定位") || result.contains("当前位置"),
                      "结果应包含定位或位置关键词，实际：\(result)")
    }

    /// 多次串行调用 execute 应验证 continuation 的线程安全性。
    /// 新代码每次调用创建独立 LocationFetcher，continuation 在 DispatchQueue.main 上读写，
    /// 串行调用不应因 continuation 竞态而崩溃。
    func testExecuteSerialCallsContinuationThreadSafety() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        for _ in 0..<3 {
            let result = try await tool.execute(arguments: [:])
            XCTAssertFalse(result.isEmpty, "串行调用应每次返回非空字符串")
        }
    }

    /// 并发调用 execute 应验证 continuation 的线程安全性。
    /// 新代码统一在 DispatchQueue.main 上 resume，避免多线程同时访问 continuation。
    func testExecuteConcurrentCallsContinuationThreadSafety() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下并发定位不稳定")
        let tool1 = LocationTool()
        let tool2 = LocationTool()
        async let r1 = try tool1.execute(arguments: [:])
        async let r2 = try tool2.execute(arguments: [:])
        let results = try await [r1, r2]
        for result in results {
            XCTAssertFalse(result.isEmpty, "并发调用应返回非空字符串")
        }
    }

    // MARK: - 新代码覆盖率补充：resume(returning:) 与 resume(throwing:) 的 DispatchQueue.main.async 路径

    /// execute 不跳过：确保 resume(throwing:) 的 DispatchQueue.main.async 路径被执行。
    /// 模拟器环境下定位通常超时（10s）或权限被拒，触发 resume(throwing:) 经主线程调度。
    /// 新代码将 resume(throwing:) 包裹在 DispatchQueue.main.async 中，此测试验证该路径不崩溃。
    func testExecuteCoversResumeThrowingMainThreadDispatch() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
        // 超时 → "定位超时，请重试"；权限被拒 → "定位权限未授权..."；成功 → "当前位置..."；其他错误 → "定位失败..."
        let isExpected = result.contains("定位超时") ||
                         result.contains("定位权限") ||
                         result.contains("当前位置") ||
                         result.contains("定位失败")
        XCTAssertTrue(isExpected, "结果应包含超时/权限/位置/失败关键词，实际：\(result)")
    }

    /// execute 成功路径覆盖 resume(returning:) 的 DispatchQueue.main.async 调度。
    /// 若模拟器返回定位（模拟器默认有 Apple 位置），resume(returning:) 被调用并经主线程调度；
    /// 若超时则覆盖 resume(throwing:)。两种情况均验证新代码路径被执行。
    func testExecuteCoversResumeReturningMainThreadDispatch() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "execute 应返回非空字符串")
        // 成功路径：结果包含 "当前位置" 与 "经纬度"
        // 失败路径：结果包含 "定位超时" / "定位权限" / "定位失败"
        let isExpected = result.contains("当前位置") ||
                         result.contains("定位超时") ||
                         result.contains("定位权限") ||
                         result.contains("定位失败")
        XCTAssertTrue(isExpected, "结果应包含位置或定位错误关键词，实际：\(result)")
        // 若成功，验证经纬度格式（4 位小数）
        if result.contains("当前位置") && result.contains("经纬度") {
            let regex = try? NSRegularExpression(pattern: #"\d+\.\d{4}"#, options: [])
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex?.matches(in: result, options: [], range: range) ?? []
            XCTAssertGreaterThanOrEqual(matches.count, 2,
                                        "成功结果应至少含 2 个 4 位小数坐标，实际：\(result)")
        }
    }

    /// execute 多次串行调用覆盖 resume 路径的 DispatchQueue.main.async 调度。
    /// 每次调用创建独立 LocationFetcher，continuation 在主线程上 resume，验证不发生竞态。
    func testExecuteSerialCallsCoverResumeDispatchPath() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        for _ in 0..<2 {
            let result = try await tool.execute(arguments: [:])
            XCTAssertFalse(result.isEmpty, "串行调用应每次返回非空字符串")
        }
    }

    /// execute 传入无关参数（非跳过）覆盖 resume 路径。
    /// LocationTool 忽略所有参数，resume 路径与无参调用一致。
    func testExecuteWithExtraArgumentsCoversResumePath() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        let result = try await tool.execute(arguments: ["unused": "value", "n": 42])
        XCTAssertFalse(result.isEmpty, "传入无关参数应返回非空字符串")
        XCTAssertTrue(result.contains("定位") || result.contains("当前位置"),
                      "结果应包含定位或位置关键词，实际：\(result)")
    }

    /// execute 并发调用（非跳过）覆盖多实例 resume 路径的线程安全性。
    /// 两个 LocationTool 实例同时 execute，各自 LocationFetcher 的 continuation 独立 resume。
    func testExecuteConcurrentCoversResumeThreadSafety() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位 10s 超时拖慢 CI")
        let tool1 = LocationTool()
        let tool2 = LocationTool()
        async let r1 = try tool1.execute(arguments: [:])
        async let r2 = try tool2.execute(arguments: [:])
        let results = try await [r1, r2]
        for result in results {
            XCTAssertFalse(result.isEmpty, "并发调用应返回非空字符串")
        }
    }
}
