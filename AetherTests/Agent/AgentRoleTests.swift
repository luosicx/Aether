import XCTest
@testable import Aether

/// Task 20 阶段 1: AgentRole 与 AgentConfig 单元测试。
///
/// 覆盖：
/// - 三个角色的 systemPrompt 非空且互不相同
/// - 角色 Codable 往返编解码
/// - AgentConfig 默认值与自定义值
/// - defaultExecutor 便捷配置
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

    /// 三个角色的 systemPrompt 互不相同
    func testSystemPromptsAreDistinct() {
        let prompts: Set<String> = [
            AgentRole.planner.systemPrompt,
            AgentRole.executor.systemPrompt,
            AgentRole.reviewer.systemPrompt,
        ]
        XCTAssertEqual(prompts.count, 3, "三个角色的 systemPrompt 应互不相同")
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

    // MARK: - AgentRole Codable

    /// 角色编解码往返应保持一致
    func testRoleCodingRoundTrip() throws {
        for role in [AgentRole.planner, .executor, .reviewer] {
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

    /// 角色的 rawValue 应为预期字符串
    func testRoleRawValues() {
        XCTAssertEqual(AgentRole.planner.rawValue, "planner")
        XCTAssertEqual(AgentRole.executor.rawValue, "executor")
        XCTAssertEqual(AgentRole.reviewer.rawValue, "reviewer")
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
}
