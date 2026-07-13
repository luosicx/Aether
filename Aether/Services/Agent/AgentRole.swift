import Foundation

/// Task 12: Agent 角色枚举。不同角色承担不同职责，支持多 Agent 协作。
///
/// 角色分工：
/// - `planner`：规划者，将用户目标分解为可执行的子任务列表
/// - `executor`：执行者，调用工具或 LLM 完成单个子任务
/// - `reviewer`：审查者，审查子任务执行结果，不通过则触发重试
enum AgentRole: String, Codable {
    /// 规划者：分解目标为子任务
    case planner
    /// 执行者：执行子任务
    case executor
    /// 审查者：审查执行结果
    case reviewer

    /// 角色对应的系统提示词，用于设定 LLM 行为
    var systemPrompt: String {
        switch self {
        case .planner:
            return "你是任务规划专家，擅长将复杂目标分解为可执行的子任务。请确保子任务清晰、可衡量、有明确的执行顺序与依赖关系。"
        case .executor:
            return "你是任务执行专家，负责高效完成分配的子任务。请给出直接、可操作的结果。"
        case .reviewer:
            return "你是代码/结果审查专家，负责审查子任务的执行结果。请判断结果是否正确、完整、达到预期目标，并给出通过或不通过的结论。"
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
