#if os(macOS)
import XCTest
@testable import Aether

final class SystemControlToolTests: XCTestCase {
    private let tool = SystemControlTool()

    func testDefinitionSchema() {
        XCTAssertEqual(tool.definition.name, "system_control")
    }

    func testExecuteMissingAction() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertEqual(result, "错误：请提供 action 参数")
    }

    func testExecuteSetVolume() async throws {
        let result = try await tool.execute(arguments: ["action": "set_volume", "value": 50])
        XCTAssertTrue(result.contains("已") || result.contains("错误"), "实际：\(result)")
    }

    // MARK: - 新代码覆盖率：getVolume 修复后的 AppleScript 语法 + setBrightnessViaGamma 返回值检查

    /// get_volume 应调用修复后的 getVolume()（AppleScript 移入 tell 块内部）。
    /// 返回值为音量数字字符串或 AppleScript 错误信息。
    func testExecuteGetVolume() async throws {
        let result = try await tool.execute(arguments: ["action": "get_volume"])
        XCTAssertFalse(result.isEmpty, "get_volume 应返回非空字符串，实际：\(result)")
        // 成功时返回数字（0-100），失败时返回 "错误：..." 前缀
        let isNumber = Int(result) != nil
        let isError = result.hasPrefix("错误")
        XCTAssertTrue(isNumber || isError,
                      "get_volume 应返回音量数字或错误，实际：\(result)")
    }

    /// set_brightness 传入有效 value 50 应调用 setBrightnessViaGamma。
    /// 新代码检查 runAppleScript 返回值前缀，失败时返回 "设置亮度失败：..."。
    /// 在测试环境中可能因辅助功能权限不足而返回错误，但不应崩溃。
    func testExecuteSetBrightnessWithValidValue() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": 50])
        // 成功时返回 "已尝试设置亮度..."；失败时返回 "设置亮度失败：错误：..."
        XCTAssertTrue(result.contains("亮度"),
                      "set_brightness 结果应包含 '亮度'，实际：\(result)")
    }

    /// set_brightness 传入边界值 0 应正常执行（不崩溃）
    func testExecuteSetBrightnessMinValue() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": 0])
        XCTAssertTrue(result.contains("亮度"),
                      "set_brightness value=0 应返回亮度相关结果，实际：\(result)")
    }

    /// set_brightness 传入边界值 100 应正常执行（不崩溃）
    func testExecuteSetBrightnessMaxValue() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": 100])
        XCTAssertTrue(result.contains("亮度"),
                      "set_brightness value=100 应返回亮度相关结果，实际：\(result)")
    }

    /// set_brightness 传入越界值 150 应返回参数错误（不调用 AppleScript）
    func testExecuteSetBrightnessOutOfRange() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": 150])
        XCTAssertEqual(result, "错误：请提供 0-100 之间的 value 参数",
                       "越界 value 应返回参数错误")
    }

    /// set_brightness 传入负值应返回参数错误
    func testExecuteSetBrightnessNegativeValue() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": -1])
        XCTAssertEqual(result, "错误：请提供 0-100 之间的 value 参数",
                       "负值 value 应返回参数错误")
    }

    /// set_brightness 缺少 value 参数应返回参数错误
    func testExecuteSetBrightnessMissingValue() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness"])
        XCTAssertEqual(result, "错误：请提供 0-100 之间的 value 参数",
                       "缺 value 应返回参数错误")
    }

    /// set_volume 传入越界值应返回参数错误
    func testExecuteSetVolumeOutOfRange() async throws {
        let result = try await tool.execute(arguments: ["action": "set_volume", "value": 200])
        XCTAssertEqual(result, "错误：请提供 0-100 之间的 value 参数",
                       "越界 value 应返回参数错误")
    }

    /// get_brightness 应返回提示字符串（macOS 无直接公开 API）
    func testExecuteGetBrightness() async throws {
        let result = try await tool.execute(arguments: ["action": "get_brightness"])
        XCTAssertFalse(result.isEmpty, "get_brightness 应返回非空字符串")
        XCTAssertTrue(result.contains("亮度") || result.contains("macOS"),
                      "get_brightness 应返回亮度相关提示，实际：\(result)")
    }

    /// 不支持的 action 应返回错误
    func testExecuteUnsupportedAction() async throws {
        let result = try await tool.execute(arguments: ["action": "unknown"])
        XCTAssertTrue(result.hasPrefix("错误"), "不支持的 action 应返回错误，实际：\(result)")
    }

    // MARK: - definition 结构验证

    /// definition.description 应非空
    func testDefinitionDescriptionNonEmpty() {
        XCTAssertFalse(tool.definition.description.isEmpty, "description 不应为空")
    }

    /// definition.parameters["type"] 应为 "object"
    func testDefinitionParametersTypeIsObject() {
        let type = tool.definition.parameters["type"] as? String
        XCTAssertEqual(type, "object", "parameters.type 应为 object")
    }

    /// definition.parameters 应含 action 和 value 两个属性
    func testDefinitionPropertiesContainsActionAndValue() {
        let properties = tool.definition.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["action"], "应含 action 属性")
        XCTAssertNotNil(properties?["value"], "应含 value 属性")
    }

    /// definition.parameters["required"] 应含 "action"
    func testDefinitionRequiredContainsAction() {
        let required = tool.definition.parameters["required"] as? [String]
        XCTAssertTrue(required?.contains("action") == true, "required 应含 action")
    }

    // MARK: - 新代码分支覆盖：setBrightnessViaGamma 错误检查 + getVolume 新脚本

    /// set_brightness 新代码：检查 runAppleScript 返回值前缀。
    /// 失败路径：AppleScript 执行失败 → result 以 "错误：" 开头 → 返回 "设置亮度失败：错误：..."
    /// 成功路径：AppleScript 执行成功 → 返回 "已尝试设置亮度（可能需要辅助功能权限）"
    /// 测试环境通常无辅助功能权限，应走失败路径；但两条路径都需验证格式正确。
    func testExecuteSetBrightnessFailurePathWrapsError() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": 50])
        if result.hasPrefix("设置亮度失败") {
            // 新代码失败路径：包装原始错误
            XCTAssertTrue(result.hasPrefix("设置亮度失败："),
                          "失败消息应以 '设置亮度失败：' 开头，实际：\(result)")
            XCTAssertTrue(result.contains("错误"),
                          "失败消息应保留原始 AppleScript 错误，实际：\(result)")
        } else {
            // 成功路径（有辅助功能权限时）
            XCTAssertEqual(result, "已尝试设置亮度（可能需要辅助功能权限）",
                           "成功路径应返回固定提示，实际：\(result)")
        }
    }

    /// set_brightness 边界值 0 的失败路径也应正确包装错误
    func testExecuteSetBrightnessMinValueFailurePath() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": 0])
        if result.hasPrefix("设置亮度失败") {
            XCTAssertTrue(result.contains("错误"),
                          "value=0 失败时应含错误详情，实际：\(result)")
        } else {
            XCTAssertEqual(result, "已尝试设置亮度（可能需要辅助功能权限）",
                           "value=0 成功时应返回固定提示，实际：\(result)")
        }
    }

    /// set_brightness 边界值 100 的失败路径也应正确包装错误
    func testExecuteSetBrightnessMaxValueFailurePath() async throws {
        let result = try await tool.execute(arguments: ["action": "set_brightness", "value": 100])
        if result.hasPrefix("设置亮度失败") {
            XCTAssertTrue(result.contains("错误"),
                          "value=100 失败时应含错误详情，实际：\(result)")
        } else {
            XCTAssertEqual(result, "已尝试设置亮度（可能需要辅助功能权限）",
                           "value=100 成功时应返回固定提示，实际：\(result)")
        }
    }

    /// get_volume 新脚本验证：return output volume of (get volume settings) 移入 tell 块。
    /// 成功时返回 0-100 的数字字符串；失败时返回 "错误：..." 前缀。
    func testExecuteGetVolumeNewScriptReturnsNumberOrError() async throws {
        let result = try await tool.execute(arguments: ["action": "get_volume"])
        if let volume = Int(result) {
            XCTAssertTrue((0...100).contains(volume),
                          "get_volume 成功时应返回 0-100 的数字，实际：\(volume)")
        } else {
            XCTAssertTrue(result.hasPrefix("错误"),
                          "get_volume 非数字结果应为错误前缀，实际：\(result)")
        }
    }

    /// get_volume 多次调用应一致返回数字或错误（验证新脚本稳定性）
    func testExecuteGetVolumeMultipleCallsConsistent() async throws {
        let result1 = try await tool.execute(arguments: ["action": "get_volume"])
        let result2 = try await tool.execute(arguments: ["action": "get_volume"])
        // 两次调用结果类型应一致（都是数字或都是错误）
        let isNumber1 = Int(result1) != nil
        let isNumber2 = Int(result2) != nil
        XCTAssertEqual(isNumber1, isNumber2,
                       "多次 get_volume 结果类型应一致，第一次：\(result1)，第二次：\(result2)")
    }
}
#endif
