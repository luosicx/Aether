import Foundation

// MARK: - AgentTeam

/// v3.0: 多 Agent 协作增强 — Agent 团队定义与编排。
///
/// 职责：
/// - 定义 Agent 团队（多个 Agent 协作完成复杂任务）
/// - 编排多 Agent 协作 DAG
/// - 提供 orchestrateTeam 方法入口
///
/// 与现有 AgentOrchestrator 关系：
/// - AgentTeam 是数据模型层，定义团队组成
/// - AgentOrchestrator.orchestrateTeam 负责实际执行
/// - ArbiterAgent 负责冲突仲裁
public struct AgentTeam: Identifiable, Sendable, Codable {

    /// 团队 ID
    public let id: UUID
    /// 团队名称
    public let name: String
    /// 团队描述
    public let description: String
    /// 团队成员（Agent 角色列表）
    public let members: [TeamMember]
    /// 创建时间
    public let createdAt: Date
    /// 是否启用冲突仲裁
    public let enableArbitration: Bool
    /// Token 预算上限（防止多 Agent 成本失控）
    public let tokenBudget: Int?

    /// 初始化
    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        members: [TeamMember],
        enableArbitration: Bool = true,
        tokenBudget: Int? = 50000
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.members = members
        self.createdAt = Date()
        self.enableArbitration = enableArbitration
        self.tokenBudget = tokenBudget
    }

    /// 成员数量
    public var memberCount: Int { members.count }

    /// 团队预设模板
    public static let templates: [String: AgentTeam] = [
        "research": AgentTeam(
            name: "研究团队",
            description: "researcher + reviewer + coordinator",
            members: [
                TeamMember(role: "researcher", isLead: false),
                TeamMember(role: "reviewer", isLead: false),
                TeamMember(role: "coordinator", isLead: true)
            ]
        ),
        "coding": AgentTeam(
            name: "编码团队",
            description: "planner + executor + reviewer",
            members: [
                TeamMember(role: "planner", isLead: true),
                TeamMember(role: "executor", isLead: false),
                TeamMember(role: "reviewer", isLead: false)
            ]
        ),
        "critique": AgentTeam(
            name: "批判团队",
            description: "researcher + critic + arbiter",
            members: [
                TeamMember(role: "researcher", isLead: false),
                TeamMember(role: "critic", isLead: false),
                TeamMember(role: "coordinator", isLead: true)
            ]
        )
    ]
}

// MARK: - TeamMember

/// 团队成员定义
public struct TeamMember: Sendable, Codable, Identifiable {

    /// 成员 ID
    public let id: UUID
    /// 角色（对应 AgentRole.rawValue）
    public let role: String
    /// 是否为团队 lead（协调者）
    public let isLead: Bool
    /// 可委派的下游角色
    public let delegates: [String]

    /// 初始化
    public init(
        id: UUID = UUID(),
        role: String,
        isLead: Bool = false,
        delegates: [String] = []
    ) {
        self.id = id
        self.role = role
        self.isLead = isLead
        self.delegates = delegates
    }
}

// MARK: - TeamOrchestrationResult

/// 团队编排执行结果
public struct TeamOrchestrationResult: Sendable {

    /// 团队 ID
    public let teamId: UUID
    /// 任务目标
    public let task: String
    /// 最终结果
    public let finalResult: String
    /// 各 Agent 中间结果
    public let agentResults: [AgentResultRecord]
    /// 仲裁结果（若有冲突）
    public let arbitrationResult: ArbiterAgent.ArbitrationResult?
    /// 总耗时（秒）
    public let durationSeconds: Double
    /// Token 消耗
    public let tokenConsumed: Int
    /// 是否成功
    public let success: Bool
    /// 失败原因（若有）
    public let failureReason: String?

    public init(
        teamId: UUID,
        task: String,
        finalResult: String,
        agentResults: [AgentResultRecord],
        arbitrationResult: ArbiterAgent.ArbitrationResult?,
        durationSeconds: Double,
        tokenConsumed: Int,
        success: Bool,
        failureReason: String? = nil
    ) {
        self.teamId = teamId
        self.task = task
        self.finalResult = finalResult
        self.agentResults = agentResults
        self.arbitrationResult = arbitrationResult
        self.durationSeconds = durationSeconds
        self.tokenConsumed = tokenConsumed
        self.success = success
        self.failureReason = failureReason
    }
}

/// 单个 Agent 执行记录
public struct AgentResultRecord: Sendable, Identifiable {

    public let id: UUID
    public let agentId: UUID
    public let role: String
    public let subTaskId: UUID
    public let result: String
    public let durationSeconds: Double
    public let tokenConsumed: Int

    public init(
        id: UUID = UUID(),
        agentId: UUID,
        role: String,
        subTaskId: UUID,
        result: String,
        durationSeconds: Double,
        tokenConsumed: Int
    ) {
        self.id = id
        self.agentId = agentId
        self.role = role
        self.subTaskId = subTaskId
        self.result = result
        self.durationSeconds = durationSeconds
        self.tokenConsumed = tokenConsumed
    }
}
