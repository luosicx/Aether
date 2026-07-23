import XCTest
@testable import Aether

/// Task 20 阶段 1: AgentRole 与 AgentConfig 单元测试。
///
/// 覆盖：
/// - 三个角色的 systemPrompt 非空且互不相同
/// - 角色 Codable 往返编解码
/// - AgentConfig 默认值与自定义值
/// - defaultExecutor 便捷配置
/// - v1.1 Phase B: 新增 researcher / critic / coordinator 三个角色的 systemPrompt、Codable、rawValue
/// - v1.1 Phase B: 新角色的 AgentConfig 配置
final class AgentRoleTests: XCTestCase {

    // MARK: - AgentRole.systemPrompt

    /// planner 角色 systemPrompt 非空
    func testPlannerSystemPromptNotEmpty() {
        XCTAssertFalse(AgentRole.planner.systemPrompt.isEmpty, "planner 的 systemPrompt 应非空")
    }

    /// executor 角色 systemPrompt 非空
    func testExecutorSystemPromptNotEmpty() {
        XCTAssertFalse(AgentRole.executor.systemPrompt.isEmpty, "executor 的 systemPrompt 应非空")
    }

    /// reviewer 角色 systemPrompt 非空
    func testReviewerSystemPromptNotEmpty() {
        XCTAssertFalse(AgentRole.reviewer.systemPrompt.isEmpty, "reviewer 的 systemPrompt 应非空")
    }

    /// v1.1 Phase B: researcher 角色 systemPrompt 非空
    func testResearcherSystemPromptNotEmpty() {
        XCTAssertFalse(AgentRole.researcher.systemPrompt.isEmpty, "researcher 的 systemPrompt 应非空")
    }

    /// v1.1 Phase B: critic 角色 systemPrompt 非空
    func testCriticSystemPromptNotEmpty() {
        XCTAssertFalse(AgentRole.critic.systemPrompt.isEmpty, "critic 的 systemPrompt 应非空")
    }

    /// v1.1 Phase B: coordinator 角色 systemPrompt 非空
    func testCoordinatorSystemPromptNotEmpty() {
        XCTAssertFalse(AgentRole.coordinator.systemPrompt.isEmpty, "coordinator 的 systemPrompt 应非空")
    }

    /// 所有六个角色的 systemPrompt 互不相同
    func testSystemPromptsAreDistinct() {
        let prompts: Set<String> = [
            AgentRole.planner.systemPrompt,
            AgentRole.executor.systemPrompt,
            AgentRole.reviewer.systemPrompt,
            AgentRole.researcher.systemPrompt,
            AgentRole.critic.systemPrompt,
            AgentRole.coordinator.systemPrompt,
        ]
        XCTAssertEqual(prompts.count, 6, "六个角色的 systemPrompt 应互不相同")
    }

    /// planner systemPrompt 应包含规划相关关键词
    func testPlannerPromptContainsPlanningKeyword() {
        let prompt = AgentRole.planner.systemPrompt
        XCTAssertTrue(prompt.contains("规划") || prompt.contains("分解"), "planner 提示词应包含规划关键词")
    }

    /// executor systemPrompt 应包含执行相关关键词
    func testExecutorPromptContainsExecutionKeyword() {
        let prompt = AgentRole.executor.systemPrompt
        XCTAssertTrue(prompt.contains("执行") || prompt.contains("完成"), "executor 提示词应包含执行关键词")
    }

    /// reviewer systemPrompt 应包含审查相关关键词
    func testReviewerPromptContainsReviewKeyword() {
        let prompt = AgentRole.reviewer.systemPrompt
        XCTAssertTrue(prompt.contains("审查") || prompt.contains("审查"), "reviewer 提示词应包含审查关键词")
    }

    /// v1.1 Phase B: researcher systemPrompt 应包含研究相关关键词
    func testResearcherPromptContainsResearchKeyword() {
        let prompt = AgentRole.researcher.systemPrompt
        XCTAssertTrue(prompt.contains("研究") || prompt.contains("调研") || prompt.contains("分析"),
                      "researcher 提示词应包含研究/调研/分析关键词")
    }

    /// v1.1 Phase B: critic systemPrompt 应包含批判相关关键词
    func testCriticPromptContainsCriticKeyword() {
        let prompt = AgentRole.critic.systemPrompt
        XCTAssertTrue(prompt.contains("批判") || prompt.contains("挑战") || prompt.contains("漏洞"),
                      "critic 提示词应包含批判/挑战/漏洞关键词")
    }

    /// v1.1 Phase B: coordinator systemPrompt 应包含协调相关关键词
    func testCoordinatorPromptContainsCoordinatorKeyword() {
        let prompt = AgentRole.coordinator.systemPrompt
        XCTAssertTrue(prompt.contains("协调") || prompt.contains("汇总") || prompt.contains("整合"),
                      "coordinator 提示词应包含协调/汇总/整合关键词")
    }

    // MARK: - AgentRole Codable

    /// 角色编解码往返应保持一致
    func testRoleCodingRoundTrip() throws {
        for role in [AgentRole.planner, .executor, .reviewer, .researcher, .critic, .coordinator] {
            let encoded = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(AgentRole.self, from: encoded)
            XCTAssertEqual(decoded, role, "编解码后应保持一致")
        }
    }

    /// 从原始字符串值解码应正确
    func testRoleDecodingFromRawValue() throws {
        let json = #""planner""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AgentRole.self, from: json)
        XCTAssertEqual(decoded, .planner)
    }

    /// v1.1 Phase B: 新角色从原始字符串值解码应正确
    func testNewRolesDecodingFromRawValue() throws {
        let researcherJSON = #""researcher""#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AgentRole.self, from: researcherJSON), .researcher)

        let criticJSON = #""critic""#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AgentRole.self, from: criticJSON), .critic)

        let coordinatorJSON = #""coordinator""#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AgentRole.self, from: coordinatorJSON), .coordinator)
    }

    /// 角色的 rawValue 应为预期字符串
    func testRoleRawValues() {
        XCTAssertEqual(AgentRole.planner.rawValue, "planner")
        XCTAssertEqual(AgentRole.executor.rawValue, "executor")
        XCTAssertEqual(AgentRole.reviewer.rawValue, "reviewer")
    }

    /// v1.1 Phase B: 新角色的 rawValue 应为预期字符串
    func testNewRoleRawValues() {
        XCTAssertEqual(AgentRole.researcher.rawValue, "researcher")
        XCTAssertEqual(AgentRole.critic.rawValue, "critic")
        XCTAssertEqual(AgentRole.coordinator.rawValue, "coordinator")
    }

    // MARK: - AgentConfig

    /// 默认初始化：model 与 tools 应为 nil
    func testConfigDefaultValues() {
        let config = AgentConfig(role: .planner)
        XCTAssertEqual(config.role, .planner)
        XCTAssertNil(config.model, "默认 model 应为 nil")
        XCTAssertNil(config.tools, "默认 tools 应为 nil")
    }

    /// 自定义 model 与 tools 应正确赋值
    func testConfigCustomValues() {
        let config = AgentConfig(role: .executor, model: "qwen-max", tools: ["search", "calculator"])
        XCTAssertEqual(config.role, .executor)
        XCTAssertEqual(config.model, "qwen-max")
        XCTAssertEqual(config.tools, ["search", "calculator"])
    }

    /// tools 为空数组（非 nil）应保留
    func testConfigEmptyToolsArray() {
        let config = AgentConfig(role: .reviewer, tools: [])
        XCTAssertEqual(config.tools, [], "空数组应保留（区别于 nil）")
        XCTAssertNotNil(config.tools)
    }

    /// defaultExecutor 应为 executor 角色
    func testDefaultExecutorConfig() {
        let config = AgentConfig.defaultExecutor
        XCTAssertEqual(config.role, .executor, "默认执行者配置应为 executor 角色")
        XCTAssertNil(config.model, "默认执行者应使用默认模型")
        XCTAssertNil(config.tools, "默认执行者应可使用全部工具")
    }

    /// model 设为指定字符串
    func testConfigWithSpecificModel() {
        let config = AgentConfig(role: .planner, model: "deepseek-chat")
        XCTAssertEqual(config.model, "deepseek-chat")
    }

    // MARK: - v1.1 Phase B: 新角色 AgentConfig

    /// researcher 角色 AgentConfig 应正确
    func testResearcherAgentConfig() {
        let config = AgentConfig(role: .researcher, model: "qwen-max", tools: ["search"])
        XCTAssertEqual(config.role, .researcher)
        XCTAssertEqual(config.model, "qwen-max")
        XCTAssertEqual(config.tools, ["search"])
    }

    /// critic 角色 AgentConfig 应正确
    func testCriticAgentConfig() {
        let config = AgentConfig(role: .critic)
        XCTAssertEqual(config.role, .critic)
        XCTAssertNil(config.model)
        XCTAssertNil(config.tools)
    }

    /// coordinator 角色 AgentConfig 应正确
    func testCoordinatorAgentConfig() {
        let config = AgentConfig(role: .coordinator, tools: [])
        XCTAssertEqual(config.role, .coordinator)
        XCTAssertNotNil(config.tools)
        XCTAssertEqual(config.tools, [])
    }

    // MARK: - v1.1 Phase B: 边界与属性测试

    /// 所有六个角色的 rawValue 均非空
    func testAllRoleRawValuesNonEmpty() {
        let roles: [AgentRole] = [.planner, .executor, .reviewer, .researcher, .critic, .coordinator]
        for role in roles {
            XCTAssertFalse(role.rawValue.isEmpty, "角色 \(role) 的 rawValue 应非空")
        }
    }

    /// 无效的 rawValue 解码应抛错
    func testDecodingInvalidRawValueThrows() {
        let invalidJSON = #""nonexistent_role""#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AgentRole.self, from: invalidJSON),
                             "无效角色字符串应抛解码错误") { error in
            guard error is DecodingError else {
                XCTFail("应为 DecodingError，实际：\(error)")
                return
            }
        }
    }

    /// 空字符串解码应抛错
    func testDecodingEmptyStringThrows() {
        let emptyJSON = #""""#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AgentRole.self, from: emptyJSON),
                             "空字符串应抛解码错误")
    }

    /// 编码后应为 JSON 字符串格式（带双引号）
    func testEncodingProducesJSONString() throws {
        let encoded = try JSONEncoder().encode(AgentRole.researcher)
        let jsonString = String(data: encoded, encoding: .utf8)
        XCTAssertEqual(jsonString, #""researcher""#, "编码应为带引号的 JSON 字符串")
    }

    /// v1.1 Phase B: 新角色单独编解码往返
    func testNewRolesIndividualRoundTrip() throws {
        for role in [AgentRole.researcher, .critic, .coordinator] {
            let encoded = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(AgentRole.self, from: encoded)
            XCTAssertEqual(decoded, role, "\(role) 编解码往返应保持一致")
        }
    }

    /// 全部六个角色均可构造 AgentConfig 并保留角色
    func testAllRolesAgentConfig() {
        let roles: [AgentRole] = [.planner, .executor, .reviewer, .researcher, .critic, .coordinator]
        for role in roles {
            let config = AgentConfig(role: role)
            XCTAssertEqual(config.role, role, "AgentConfig 应保留角色 \(role)")
            XCTAssertNil(config.model, "未指定 model 时应为 nil")
            XCTAssertNil(config.tools, "未指定 tools 时应为 nil")
        }
    }

    /// defaultExecutor 应与手动构造的 executor 配置一致
    func testDefaultExecutorEqualsManualConfig() {
        let manual = AgentConfig(role: .executor, model: nil, tools: nil)
        XCTAssertEqual(AgentConfig.defaultExecutor.role, manual.role)
        XCTAssertEqual(AgentConfig.defaultExecutor.model, manual.model)
        XCTAssertEqual(AgentConfig.defaultExecutor.tools, manual.tools)
    }

    /// AgentConfig 字段一致性比较（相同字段应产生相同值）
    func testAgentConfigFieldConsistency() {
        let config1 = AgentConfig(role: .researcher, model: "qwen-max", tools: ["search"])
        let config2 = AgentConfig(role: .researcher, model: "qwen-max", tools: ["search"])
        let config3 = AgentConfig(role: .researcher, model: "qwen-max", tools: ["calculator"])

        XCTAssertEqual(config1.role, config2.role)
        XCTAssertEqual(config1.model, config2.model)
        XCTAssertEqual(config1.tools, config2.tools)
        XCTAssertNotEqual(config1.tools, config3.tools, "tools 不同应可区分")
    }

    /// 不同角色构造的 AgentConfig 角色字段应可区分
    func testAgentConfigDifferentRolesDistinguishable() {
        let researcherConfig = AgentConfig(role: .researcher)
        let criticConfig = AgentConfig(role: .critic)
        XCTAssertNotEqual(researcherConfig.role, criticConfig.role, "不同角色应可区分")
    }

    /// 新角色 systemPrompt 长度应合理（至少 10 字符，避免空提示词）
    func testNewRoleSystemPromptSufficientLength() {
        let minLen = 10
        XCTAssertGreaterThanOrEqual(AgentRole.researcher.systemPrompt.count, minLen,
                                    "researcher systemPrompt 长度应 ≥ \(minLen)")
        XCTAssertGreaterThanOrEqual(AgentRole.critic.systemPrompt.count, minLen,
                                    "critic systemPrompt 长度应 ≥ \(minLen)")
        XCTAssertGreaterThanOrEqual(AgentRole.coordinator.systemPrompt.count, minLen,
                                    "coordinator systemPrompt 长度应 ≥ \(minLen)")
    }

    /// 新角色 systemPrompt 应包含中文（避免回退到英文占位符）
    func testNewRoleSystemPromptContainsChinese() {
        let chineseRegex = try? NSRegularExpression(pattern: "[\\u4e00-\\u9fff]")
        for role in [AgentRole.researcher, .critic, .coordinator] {
            let prompt = role.systemPrompt
            let range = NSRange(prompt.startIndex..., in: prompt)
            let matchCount = chineseRegex?.numberOfMatches(in: prompt, range: range) ?? 0
            XCTAssertGreaterThan(matchCount, 0, "\(role) systemPrompt 应包含中文字符")
        }
    }
}
