import Foundation
import AetherFoundation

/// v1.1 Phase B: 独立 Agent 实例。
///
/// 表示一个具有特定角色与配置的 Agent，可独立执行子任务。
/// 与 `AgentOrchestrator` 的单 Orchestrator 内角色切换不同，
/// `AgentInstance` 是一个可被引用、可被委派的独立执行单元，
/// 支持跨 Agent 协作。
///
/// 设计要点：
/// - `@MainActor` 隔离，保证 `conversationHistory` 等可变状态的线程安全
/// - `execute(subTask:llmProvider:)` 委托 `LLMProvider` 发送 LLM 请求
/// - 按 `role.systemPrompt` 构造请求，保留多轮对话历史
/// - 与 `AgentMessageBus` 解耦：实例本身不直接收发消息，由 orchestrator 协调
@MainActor
final class AgentInstance {

    /// Agent 实例错误
    enum AgentInstanceError: Error, LocalizedError {
        /// LLM 返回内容为空
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Agent 执行子任务时 LLM 返回为空"
            }
        }
    }

    /// 实例唯一标识
    let id: UUID
    /// 角色职责（决定 systemPrompt）
    let role: AgentRole
    /// Agent 配置（模型、可用工具范围）
    let config: AgentConfig
    /// 当前状态
    private(set) var status: AgentStatus = .idle
    /// 对话历史（按角色 systemPrompt + 历次 user/assistant 消息累积）
    private(set) var conversationHistory: [APIMessage] = []

    /// 创建 AgentInstance
    /// - Parameters:
    ///   - id: 实例 ID，默认自动生成
    ///   - role: 角色
    ///   - config: 配置，默认使用该角色的配置（model=nil，tools=nil）
    init(id: UUID = UUID(), role: AgentRole, config: AgentConfig? = nil) {
        self.id = id
        self.role = role
        self.config = config ?? AgentConfig(role: role)
    }

    /// 执行子任务：按角色 systemPrompt 构建 LLM 请求并返回结果
    ///
    /// 流程：
    /// 1. 标记状态为 `executing`
    /// 2. 以 `role.systemPrompt` 作为 system 消息，构造 user 消息
    /// 3. 调用 `LLMProvider.chat` 流式累积响应
    /// 4. 更新 `conversationHistory`，标记状态为 `idle`
    /// - Parameters:
    ///   - subTask: 待执行的子任务
    ///   - llmProvider: LLM 供应商
    /// - Returns: LLM 返回的执行结果字符串
    /// - Throws: `AgentInstanceError.emptyResponse`
    func execute(subTask: SubTask, llmProvider: LLMProvider) async throws -> String {
        status = .executing

        let systemPrompt = role.systemPrompt
        let userContent = """
        子任务：\(subTask.title)
        描述：\(subTask.description)
        请以 \(role.rawValue) 角色身份执行此子任务并给出结果。
        """

        let messages: [APIMessage] = [
            APIMessage(role: "system", content: systemPrompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: userContent, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]

        let model = config.model ?? ChatConfig.default.model
        let chatConfig = ChatConfig(model: model, systemPrompt: systemPrompt, maxTokens: 2048, temperature: 0.7)

        var result = ""
        let stream = llmProvider.chat(messages: messages, config: chatConfig, apiKey: "")
        for await chunk in stream {
            result += chunk
        }

        // 更新对话历史（保留 system + user + assistant）
        conversationHistory.append(contentsOf: messages)
        conversationHistory.append(APIMessage(role: "assistant", content: result, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil))

        status = .idle

        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentInstanceError.emptyResponse
        }

        return result
    }

    /// 重置 Agent 状态与对话历史（不影响 id/role/config）
    func reset() {
        status = .idle
        conversationHistory.removeAll()
    }
}

/// v1.1 Phase B: Agent 状态枚举
enum AgentStatus: String, Codable, Sendable {
    /// 空闲
    case idle
    /// 执行中
    case executing
    /// 等待委派结果
    case waitingForDelegation
    /// 已停止
    case stopped
}
