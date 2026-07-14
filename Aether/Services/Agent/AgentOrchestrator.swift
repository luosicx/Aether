import Foundation
import SwiftData
import AetherFoundation

/// Task 10/11/12: Agent 任务编排引擎。
///
/// 职责：
/// - **Task 10**：目标分解、子任务 DAG 调度执行、任务取消
/// - **Task 11**：每个子任务完成后持久化状态、启动时自动恢复未完成任务
/// - **Task 12**：基于 AgentRole 的多 Agent 协作（planner 分解 / executor 执行 / reviewer 审查）
///
/// 设计要点：
/// - `@MainActor` 隔离，保证 ModelContext 与 currentTask 的线程安全
/// - 子任务按 DAG 依赖顺序执行：`nextExecutableSubTask()` 返回依赖已完成的 pending 子任务
/// - 审查流程：`enableReview = true` 时，每个子任务执行后由 reviewer 角色审查，不通过则重试
@MainActor
final class AgentOrchestrator {

    /// 编排引擎错误类型
    enum OrchestratorError: Error, LocalizedError {
        /// 当前没有正在执行的任务
        case noActiveTask
        /// 没有可执行的子任务
        case noExecutableSubTask
        /// 子任务执行失败，携带子任务 ID 与原因
        case subTaskFailed(UUID, String)
        /// 审查未通过，携带子任务 ID 与原因
        case reviewFailed(UUID, String)

        var errorDescription: String? {
            switch self {
            case .noActiveTask:
                return "当前没有正在执行的任务"
            case .noExecutableSubTask:
                return "没有可执行的子任务"
            case .subTaskFailed(let id, let reason):
                return "子任务 \(id) 执行失败：\(reason)"
            case .reviewFailed(let id, let reason):
                return "子任务 \(id) 审查未通过：\(reason)"
            }
        }
    }

    /// 数据上下文（SwiftData）
    private let modelContext: ModelContext
    /// LLM 供应商
    private let llmProvider: LLMProvider
    /// 目标分解器（planner 角色使用）
    private let goalDecomposer: GoalDecomposer

    /// Agent 配置（角色、模型、工具范围）
    var agentConfig: AgentConfig

    /// 是否启用审查者角色（多 Agent 协作）。默认 false。
    /// 设为 true 后，每个子任务执行完毕由 reviewer 角色审查结果，不通过则重试。
    var enableReview: Bool = false

    /// 当前执行的任务
    private(set) var currentTask: AgentTask?

    /// 审查失败后的最大重试次数
    private let maxReviewRetries = 3

    /// 创建 AgentOrchestrator
    /// - Parameters:
    ///   - modelContext: SwiftData 数据上下文
    ///   - llmProvider: LLM 供应商
    ///   - agentConfig: Agent 配置，默认为 executor 角色
    init(modelContext: ModelContext, llmProvider: LLMProvider, agentConfig: AgentConfig = .defaultExecutor) {
        self.modelContext = modelContext
        self.llmProvider = llmProvider
        self.goalDecomposer = GoalDecomposer(llmProvider: llmProvider)
        self.agentConfig = agentConfig

        // Task 11.2: 启动时检查并恢复未完成的任务
        try? resumeInProgressTask()
    }

    // MARK: - Task 10: 任务编排

    /// 启动任务：创建 AgentTask、使用 planner 角色分解目标、持久化
    /// - Parameters:
    ///   - goal: 用户原始目标
    ///   - conversationID: 关联会话 ID，可选
    /// - Returns: 创建并分解后的 AgentTask
    func startTask(goal: String, conversationID: UUID? = nil) async throws -> AgentTask {
        // 1. 创建任务并标记为进行中
        let task = AgentTask(goal: goal, conversationID: conversationID)
        task.markInProgress()

        // 2. 插入到 context
        modelContext.insert(task)

        // 3. Task 12: 使用 planner 角色分解目标
        let subTasks = try await goalDecomposer.decompose(goal: goal)
        task.updateSubTasks(subTasks)

        // 4. Task 11.1: 持久化
        try modelContext.save()

        // 5. 设为当前任务
        currentTask = task

        return task
    }

    /// 执行下一个子任务
    /// - Throws: `OrchestratorError.noActiveTask`（无当前任务）、`.noExecutableSubTask`（无可执行子任务）
    func executeNext() async throws {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }

        guard let subTask = task.nextExecutableSubTask() else {
            // 没有可执行的子任务：若全部完成则标记完成，否则标记失败
            if task.isAllSubTasksCompleted {
                task.markCompleted()
                try modelContext.save()
            }
            throw OrchestratorError.noExecutableSubTask
        }

        try await executeSubTask(subTask)
    }

    /// 执行所有子任务（DAG 调度）
    ///
    /// 循环获取 `nextExecutableSubTask()`，按依赖顺序逐个执行。
    /// 无依赖的子任务按 `order` 顺序执行；有依赖的子任务等待依赖完成后执行。
    /// 每个子任务完成后持久化状态，支持断点续执行。
    /// - Throws: `OrchestratorError.noActiveTask` 或子任务执行错误
    func executeAll() async throws {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }

        // 循环执行直到所有子任务完成
        while !task.isAllSubTasksCompleted {
            // 获取当前可执行的子任务（pending 且依赖全部完成）
            guard let subTask = task.nextExecutableSubTask() else {
                // 没有可执行的子任务
                if task.isAllSubTasksCompleted {
                    task.markCompleted()
                } else {
                    // 可能存在失败导致无法继续
                    task.markFailed()
                }
                try modelContext.save()
                return
            }

            // 执行单个子任务（含状态管理和审查）
            try await executeSubTask(subTask)
        }

        // 所有子任务完成，标记任务完成
        task.markCompleted()
        try modelContext.save()
    }

    /// 取消当前任务
    /// - Throws: `OrchestratorError.noActiveTask`
    func cancel() throws {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }
        task.cancel()
        try modelContext.save()
    }

    // MARK: - Task 11: 断点续执行

    /// 恢复指定任务
    ///
    /// 将给定任务设为当前任务并标记为 inProgress，随后可调用 `executeAll()` 继续执行。
    /// - Parameter task: 待恢复的 AgentTask
    func resumeTask(_ task: AgentTask) async throws {
        task.markInProgress()
        currentTask = task
        try modelContext.save()
    }

    // MARK: - 私有方法

    /// 执行单个子任务（含状态管理和审查）
    ///
    /// 流程：标记 inProgress → 执行（工具/LLM）→ 审查（可选）→ 标记 completed/failed → 持久化
    /// - Parameter subTask: 待执行的子任务
    /// - Returns: 执行结果字符串
    private func executeSubTask(_ subTask: SubTask) async throws -> String {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }

        // 标记为进行中
        _ = task.updateSubTaskStatus(id: subTask.id, status: .inProgress)
        try modelContext.save()

        var result: String
        do {
            result = try await performSubTaskExecution(subTask)
        } catch {
            // 执行失败：更新状态并持久化
            _ = task.updateSubTaskStatus(id: subTask.id, status: .failed, result: error.localizedDescription)
            try modelContext.save()
            throw OrchestratorError.subTaskFailed(subTask.id, error.localizedDescription)
        }

        // 更新结果并标记完成
        _ = task.updateSubTaskStatus(id: subTask.id, status: .completed, result: result)

        // Task 11.1: 每个子任务完成后持久化状态
        try modelContext.save()

        return result
    }

    /// 执行子任务核心逻辑（不含状态管理），支持工具和 LLM 执行及审查重试
    ///
    /// Task 12: 根据 AgentRole 进行角色调度：
    /// - executor 角色：执行子任务（调用工具或 LLM）
    /// - reviewer 角色：审查执行结果，不通过则重新执行
    /// - Parameter subTask: 待执行的子任务
    /// - Returns: 执行结果字符串
    private func performSubTaskExecution(_ subTask: SubTask) async throws -> String {
        var result: String

        // 如果指定了工具，调用 ToolRegistry 执行
        if let toolName = subTask.toolName {
            result = try await executeWithTool(name: toolName)
        } else {
            // 否则使用 executor 角色 systemPrompt 调用 LLM 执行
            result = try await executeWithLLM(subTask: subTask)
        }

        // Task 12: 审查者角色审查结果
        if enableReview {
            var attempts = 0
            while attempts < maxReviewRetries {
                let passed = try await reviewResult(subTask: subTask, result: result)
                if passed { break }
                attempts += 1
                // 审查未通过，重新执行
                if let toolName = subTask.toolName {
                    result = try await executeWithTool(name: toolName)
                } else {
                    result = try await executeWithLLM(subTask: subTask)
                }
            }
        }

        return result
    }

    /// 使用 LLM 执行子任务（executor 角色）
    /// - Parameter subTask: 待执行的子任务
    /// - Returns: LLM 返回的执行结果
    private func executeWithLLM(subTask: SubTask) async throws -> String {
        let systemPrompt = AgentRole.executor.systemPrompt
        let userContent = """
        子任务：\(subTask.title)
        描述：\(subTask.description)
        请执行此子任务并给出结果。
        """

        let messages: [APIMessage] = [
            APIMessage(role: "system", content: systemPrompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: userContent, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]

        let model = agentConfig.model ?? ChatConfig.default.model
        let config = ChatConfig(model: model, systemPrompt: systemPrompt, maxTokens: 2048, temperature: 0.7)

        let stream = llmProvider.chat(messages: messages, config: config, apiKey: "")
        var result = ""
        for await chunk in stream {
            result += chunk
        }
        return result
    }

    /// 使用工具执行子任务
    /// - Parameter name: 工具名（对应 ToolRegistry 中注册的工具）
    /// - Returns: 工具执行结果字符串
    private func executeWithTool(name: String) async throws -> String {
        return try await ToolRegistry.shared.execute(name: name, arguments: [:])
    }

    /// Task 12: 审查者角色审查执行结果
    /// - Parameters:
    ///   - subTask: 被审查的子任务
    ///   - result: 执行结果
    /// - Returns: true 表示审查通过，false 表示不通过
    private func reviewResult(subTask: SubTask, result: String) async throws -> Bool {
        let systemPrompt = AgentRole.reviewer.systemPrompt
        let userContent = """
        子任务：\(subTask.title)
        描述：\(subTask.description)
        执行结果：\(result)

        请审查此结果是否正确、完整。回复"通过"或"不通过"，并说明原因。
        """

        let messages: [APIMessage] = [
            APIMessage(role: "system", content: systemPrompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: userContent, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]

        let config = ChatConfig(model: ChatConfig.default.model, systemPrompt: systemPrompt, maxTokens: 512, temperature: 0.3)

        let stream = llmProvider.chat(messages: messages, config: config, apiKey: "")
        var response = ""
        for await chunk in stream {
            response += chunk
        }

        // 简单判断：包含"通过"且不包含"不通过"则为通过
        return response.contains("通过") && !response.contains("不通过")
    }

    /// Task 11.2: 启动时恢复未完成的任务
    ///
    /// 查找 status == .inProgress 的 AgentTask，设为当前任务。
    /// 若存在多个，取第一个。
    private func resumeInProgressTask() throws {
        let descriptor = FetchDescriptor<AgentTask>()
        let tasks = try modelContext.fetch(descriptor)
        if let inProgressTask = tasks.first(where: { $0.status == .inProgress }) {
            currentTask = inProgressTask
        }
    }
}
