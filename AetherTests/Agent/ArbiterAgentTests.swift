import XCTest
@testable import Aether

/// v3.0: 多 Agent 协作增强测试（ArbiterAgent + AgentTeam）
final class ArbiterAgentTests: XCTestCase {

    // MARK: - ArbiterAgent 基本属性

    func testArbiterInitDefaults() {
        let arbiter = ArbiterAgent()
        XCTAssertEqual(arbiter.maxRounds, 5, "默认最大轮次应为 5")
        XCTAssertEqual(arbiter.currentRound, 0, "初始轮次应为 0")
    }

    func testArbiterCustomMaxRounds() {
        let arbiter = ArbiterAgent(maxRounds: 10)
        XCTAssertEqual(arbiter.maxRounds, 10)
    }

    func testArbiterReset() {
        let arbiter = ArbiterAgent()
        let results = [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "A", confidence: 0.9),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "B", confidence: 0.8)
        ]
        _ = arbiter.arbitrate(results: results)
        XCTAssertGreaterThan(arbiter.currentRound, 0)
        arbiter.reset()
        XCTAssertEqual(arbiter.currentRound, 0)
    }

    // MARK: - 多数表决

    func testMajorityVoteSingleResult() {
        let arbiter = ArbiterAgent()
        let result = arbiter.arbitrate(results: [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "唯一答案", confidence: 0.9)
        ])
        XCTAssertEqual(result.strategy, .majority)
        XCTAssertEqual(result.result, "唯一答案")
        XCTAssertNotNil(result.winnerAgentId)
    }

    func testMajorityVoteAllAgree() {
        let arbiter = ArbiterAgent()
        let result = arbiter.arbitrate(results: [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案A", confidence: 0.9),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "researcher", result: "答案A", confidence: 0.85),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "reviewer", result: "答案A", confidence: 0.95)
        ])
        XCTAssertEqual(result.strategy, .majority)
        XCTAssertEqual(result.result, "答案A")
        XCTAssertTrue(result.reason.contains("多数表决"))
    }

    func testMajorityVoteTwoThirds() {
        let arbiter = ArbiterAgent()
        let result = arbiter.arbitrate(results: [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案A", confidence: 0.9),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案A", confidence: 0.8),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案B", confidence: 0.95)
        ])
        // 2/3 = 66.7% ≥ 60%，应通过多数表决
        XCTAssertEqual(result.strategy, .majority)
        XCTAssertEqual(result.result, "答案A")
    }

    func testMajorityVoteNoMajority() {
        let arbiter = ArbiterAgent()
        let result = arbiter.arbitrate(results: [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案A", confidence: 0.9),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案B", confidence: 0.9),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案C", confidence: 0.9)
        ])
        // 各占 33.3%，无法通过多数表决，应走优先级
        XCTAssertEqual(result.strategy, .priority)
    }

    // MARK: - 优先级仲裁

    func testPriorityResolution() {
        let arbiter = ArbiterAgent()
        let result = arbiter.arbitrate(results: [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案A", confidence: 0.9),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "reviewer", result: "答案B", confidence: 0.8)
        ])
        // reviewer 优先级高于 executor
        XCTAssertEqual(result.strategy, .priority)
        XCTAssertEqual(result.result, "答案B")
        XCTAssertTrue(result.reason.contains("reviewer"))
    }

    func testPrioritySameRoleByConfidence() {
        let arbiter = ArbiterAgent()
        let result = arbiter.arbitrate(results: [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案A", confidence: 0.7),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案B", confidence: 0.9)
        ])
        // 同角色按置信度
        XCTAssertEqual(result.result, "答案B")
    }

    func testPriorityResearcherOverExecutor() {
        let arbiter = ArbiterAgent()
        let result = arbiter.arbitrate(results: [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "答案A", confidence: 0.95),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "researcher", result: "答案B", confidence: 0.5)
        ])
        // researcher 优先级高于 executor
        XCTAssertEqual(result.result, "答案B")
    }

    // MARK: - 用户介入

    func testMaxRoundsExceeded() {
        let arbiter = ArbiterAgent(maxRounds: 2)
        let results = [
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "A", confidence: 0.9),
            ArbiterAgent.AgentResult(agentId: UUID(), role: "executor", result: "B", confidence: 0.9)
        ]
        _ = arbiter.arbitrate(results: results)
        _ = arbiter.arbitrate(results: results)
        let result = arbiter.arbitrate(results: results)
        // 第 3 轮超过 maxRounds=2
        XCTAssertEqual(result.strategy, .userIntervention)
        XCTAssertTrue(result.reason.contains("最大仲裁轮次"))
    }

    // MARK: - AgentTeam 测试

    func testTeamInitDefaults() {
        let team = AgentTeam(
            name: "测试团队",
            members: [TeamMember(role: "executor")]
        )
        XCTAssertEqual(team.name, "测试团队")
        XCTAssertEqual(team.memberCount, 1)
        XCTAssertTrue(team.enableArbitration)
        XCTAssertEqual(team.tokenBudget, 50000)
        XCTAssertNotNil(team.id)
    }

    func testTeamCustomConfig() {
        let team = AgentTeam(
            name: "自定义",
            description: "描述",
            members: [TeamMember(role: "executor"), TeamMember(role: "reviewer")],
            enableArbitration: false,
            tokenBudget: 10000
        )
        XCTAssertEqual(team.memberCount, 2)
        XCTAssertFalse(team.enableArbitration)
        XCTAssertEqual(team.tokenBudget, 10000)
        XCTAssertEqual(team.description, "描述")
    }

    func testTeamTemplateResearch() {
        let team = AgentTeam.templates["research"]!
        XCTAssertEqual(team.name, "研究团队")
        XCTAssertEqual(team.memberCount, 3)
        XCTAssertTrue(team.members.contains(where: { $0.role == "researcher" }))
    }

    func testTeamTemplateCoding() {
        let team = AgentTeam.templates["coding"]!
        XCTAssertEqual(team.name, "编码团队")
        XCTAssertEqual(team.memberCount, 3)
        XCTAssertTrue(team.members.contains(where: { $0.role == "planner" && $0.isLead }))
    }

    func testTeamTemplateCritique() {
        let team = AgentTeam.templates["critique"]!
        XCTAssertEqual(team.memberCount, 3)
        XCTAssertTrue(team.members.contains(where: { $0.role == "critic" }))
    }

    func testTeamMemberInit() {
        let member = TeamMember(role: "reviewer", isLead: true, delegates: ["executor"])
        XCTAssertEqual(member.role, "reviewer")
        XCTAssertTrue(member.isLead)
        XCTAssertEqual(member.delegates, ["executor"])
        XCTAssertNotNil(member.id)
    }

    func testTeamCodable() throws {
        let team = AgentTeam(
            name: "编码测试",
            members: [TeamMember(role: "executor")]
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(team)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentTeam.self, from: data)
        XCTAssertEqual(decoded.name, team.name)
        XCTAssertEqual(decoded.memberCount, team.memberCount)
    }

    func testTeamOrchestrationResult() {
        let result = TeamOrchestrationResult(
            teamId: UUID(),
            task: "测试任务",
            finalResult: "最终结果",
            agentResults: [],
            arbitrationResult: nil,
            durationSeconds: 1.5,
            tokenConsumed: 100,
            success: true
        )
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.finalResult, "最终结果")
        XCTAssertEqual(result.tokenConsumed, 100)
    }

    func testAgentResultRecord() {
        let record = AgentResultRecord(
            agentId: UUID(),
            role: "executor",
            subTaskId: UUID(),
            result: "执行结果",
            durationSeconds: 0.5,
            tokenConsumed: 50
        )
        XCTAssertEqual(record.role, "executor")
        XCTAssertEqual(record.tokenConsumed, 50)
        XCTAssertNotNil(record.id)
    }
}
