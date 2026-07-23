import Foundation

/// Task 12: Agent 角色枚举。不同角色承担不同职责，支持多 Agent 协作。
///
/// 角色分工：
/// - `planner`：规划者，将用户目标分解为可执行的子任务列表
/// - `executor`：执行者，调用工具或 LLM 完成单个子任务
/// - `reviewer`：审查者，审查子任务执行结果，不通过则触发重试
/// - `researcher`：研究与分析，负责调研背景信息、收集证据
/// - `critic`：批判性审查，从对立视角挑战假设与结论
/// - `coordinator`：协调与汇总，整合多 Agent 输出形成最终结论
enum AgentRole: String, Codable {
    /// 规划者：分解目标为子任务
    case planner
    /// 执行者：执行子任务
    case executor
    /// 审查者：审查执行结果
    case reviewer
    /// v1.1 Phase B: 研究者，负责调研背景信息、收集证据
    case researcher
    /// v1.1 Phase B: 批判者，从对立视角挑战假设与结论
    case critic
    /// v1.1 Phase B: 协调者，整合多 Agent 输出形成最终结论
    case coordinator

    /// 角色对应的系统提示词，用于设定 LLM 行为
    var systemPrompt: String {
        switch self {
        case .planner:
            return "你是任务规划专家，擅长将复杂目标分解为可执行的子任务。请确保子任务清晰、可衡量、有明确的执行顺序与依赖关系。"
        case .executor:
            return "你是任务执行专家，负责高效完成分配的子任务。请给出直接、可操作的结果。"
        case .reviewer:
            return "你是代码/结果审查专家，负责审查子任务的执行结果。请判断结果是否正确、完整、达到预期目标，并给出通过或不通过的结论。"
        case .researcher:
            return "你是研究与分析专家，擅长调研背景信息、收集证据、整理事实。请基于可靠来源给出客观、详尽的分析结论，并标注信息来源与不确定性。"
        case .critic:
            return "你是批判性审查专家，从对立视角挑战已有假设、论证与结论。请指出潜在的逻辑漏洞、证据不足或风险点，不放过任何可疑之处，并给出改进建议。"
        case .coordinator:
            return "你是协调与汇总专家，负责整合多个 Agent 的输出，化解分歧、形成一致的最终结论。请给出结构化、可执行的汇总结果，并明确各部分的责任来源。"
        }
    }
}

/// Task 12: Agent 配置。定义 Agent 的角色、使用的模型与可用工具范围。
struct AgentConfig {
    /// 角色职责
    let role: AgentRole
    /// 使用的模型名（nil 表示使用默认模型）
    let model: String?
    /// 限制可用工具列表（nil 表示全部可用）
    let tools: [String]?

    /// 创建 AgentConfig
    /// - Parameters:
    ///   - role: 角色职责
    ///   - model: 使用的模型名，默认 nil 表示用默认模型
    ///   - tools: 可用工具列表，默认 nil 表示全部可用
    init(role: AgentRole, model: String? = nil, tools: [String]? = nil) {
        self.role = role
        self.model = model
        self.tools = tools
    }

    /// 默认执行者配置：executor 角色，全部工具可用，使用默认模型
    static let defaultExecutor = AgentConfig(role: .executor)
}
