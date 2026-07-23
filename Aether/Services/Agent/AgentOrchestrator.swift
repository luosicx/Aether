import Foundation
import SwiftData
import os
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
        /// 子任务执行失败，携带子任务 ID 与原因（向后兼容变体，不保留原始 Error 上下文）
        case subTaskFailed(UUID, String)
        /// 子任务执行失败，携带子任务 ID、原因与底层错误。
        /// - Parameters:
        ///   - id: 子任务 ID
        ///   - reason: 用户可见的错误信息（通常为 `error.localizedDescription`）
        ///   - underlying: 原始底层错误，保留用于诊断
        case subTaskFailedWithCause(id: UUID, reason: String, underlying: Error)
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
            case .subTaskFailedWithCause(let id, let reason, _):
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

    /// v1.1 Phase B: 持有的 Agent 实例字典（ID → AgentInstance）。
    ///
    /// 通过 `createAgent(role:)` 创建并注册，DAG 引擎按 `subTask.assignedRole`
    /// 或 `subTask.delegatedTo` 路由到对应实例执行。
    /// 默认为空：未创建任何 AgentInstance 时回退到单 Agent 流程（向后兼容）。
    private(set) var agentInstances: [UUID: AgentInstance] = [:]

    /// v1.1 Phase B: 角色到 Agent 实例 ID 的快速索引（同一角色可有多个实例，取首个）。
    /// 用于按 `subTask.assignedRole` 路由。
    private var roleIndex: [AgentRole: UUID] = [:]

    /// v1.1 Phase B: Agent 消息总线（跨 Agent 委派通信）。
    let messageBus: AgentMessageBus = AgentMessageBus()

    /// 当前执行的任务
    private(set) var currentTask: AgentTask?

    /// 审查失败后的最大重试次数
    private let maxReviewRetries = 3

    /// Task 20: DAG 执行引擎（懒加载）
    private lazy var dagEngine: DAGExecutionEngine = {
        let engine = DAGExecutionEngine(
            checkpointManager: CheckpointManager(modelContext: modelContext)
        )
        // 进度回调：每节点完成时持久化
        engine.onProgress = { [weak self] task in
            do {
                try self?.modelContext.save()
            } catch {
                // 进度持久化失败：检查点机制会在下次 flush 时重试，但日志需可见
                Logger.agent.error("DAG 进度回调 modelContext.save 失败 (taskID=\(task.id, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }
        // 节点失败回调：可由上层订阅触发 UI 干预
        engine.onNodeFailed = { _ in
            // 失败时 engine 已标记 failed 状态，UI 层通过 @Published 监听
        }
        // v1.1 Phase B: 注入消息总线供 executor 闭包处理跨 Agent 委派
        engine.messageBus = self.messageBus
        return engine
    }()

    /// Task 20: 用户干预回调（节点失败时触发，UI 层订阅）
    /// 参数为失败的 SubTask
    var onNodeFailed: ((SubTask) -> Void)? {
        get { dagEngine.onNodeFailed }
        set { dagEngine.onNodeFailed = newValue }
    }

    /// Task 20: 进度更新回调
    var onProgress: ((AgentTask) -> Void)? {
        get { dagEngine.onProgress }
        set { dagEngine.onProgress = newValue }
    }

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
        do {
            try resumeInProgressTask()
        } catch {
            // 启动恢复失败：不阻塞 AgentOrchestrator 初始化，记录日志便于排查
            // 用户视角：未完成任务不会自动续执行，但可手动从历史记录中恢复
            Logger.agent.error("启动恢复未完成任务失败 (用户可手动从历史记录恢复): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Task 10: 任务编排

    // MARK: - v1.1 Phase B: 多 Agent 实例管理

    /// v1.1 Phase B: 创建并注册一个 Agent 实例。
    ///
    /// 创建指定角色的 `AgentInstance`，加入 `agentInstances` 字典并更新角色索引。
    /// DAG 引擎在执行时按 `subTask.assignedRole` 通过角色索引查找实例，
    /// 或按 `subTask.delegatedTo` 直接按 ID 查找。
    /// - Parameter role: Agent 角色
    /// - Returns: 新建 Agent 实例的 ID
    @discardableResult
    func createAgent(role: AgentRole) -> UUID {
        let instance = AgentInstance(role: role)
        agentInstances[instance.id] = instance
        // 角色索引：仅在该角色尚无实例时记录（取首个）
        if roleIndex[role] == nil {
            roleIndex[role] = instance.id
        }
        return instance.id
    }

    /// v1.1 Phase B: 按 ID 获取 Agent 实例
    /// - Parameter id: Agent 实例 ID
    /// - Returns: 对应的 AgentInstance，不存在返回 nil
    func agentInstance(id: UUID) -> AgentInstance? {
        agentInstances[id]
    }

    /// v1.1 Phase B: 按角色查找已注册的 Agent 实例 ID（取首个匹配）
    /// - Parameter role: Agent 角色
    /// - Returns: 该角色的首个实例 ID，不存在返回 nil
    func agentID(forRole role: AgentRole) -> UUID? {
        roleIndex[role]
    }

    /// v1.1 Phase B: 移除指定 Agent 实例
    /// - Parameter id: Agent 实例 ID
    func removeAgent(id: UUID) {
        guard let instance = agentInstances.removeValue(forKey: id) else { return }
        // 若该实例正是角色索引中的首个，重建索引
        if roleIndex[instance.role] == id {
            roleIndex[instance.role] = agentInstances.first(where: { $0.value.role == instance.role })?.key
        }
    }

    /// v1.1 Phase B: 路由子任务到对应 Agent 实例执行。
    ///
    /// 路由策略（按优先级）：
    /// 1. `subTask.delegatedTo` 非空：直接路由到指定 Agent 实例
    /// 2. `subTask.assignedRole` 非空：通过角色索引查找匹配实例
    /// 3. 兜底：返回 nil，调用方回退到默认 executor 流程（向后兼容）
    /// - Parameter subTask: 待路由的子任务
    /// - Returns: 匹配的 AgentInstance，无匹配返回 nil
    func routeToAgent(subTask: SubTask) -> AgentInstance? {
        if let delegatedID = subTask.delegatedTo, let instance = agentInstances[delegatedID] {
            return instance
        }
        if let role = subTask.assignedRole, let id = roleIndex[role], let instance = agentInstances[id] {
            return instance
        }
        return nil
    }


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
    /// Task 20: 内部委托给 `DAGExecutionEngine` 进行并行 DAG 调度，
    /// 对外接口（`startTask` / `executeAll` / `cancel`）保持不变，现有调用方零改动。
    ///
    /// 引擎行为：
    /// - 获取所有依赖已就绪的 pending 节点，并行提交执行（最大并发 4）
    /// - 节点失败按指数退避重试（1s/2s/4s，最大 3 次）
    /// - 每节点完成即检查点持久化
    /// - 失败节点用尽重试后标记 failed，触发 `onNodeFailed` 回调
    /// - 跳过 failed 节点的下游依赖（自动级联 skipped）
    ///
    /// v1.1 Phase B: 多 Agent 路由与委派
    /// - `subTask.assignedRole` 非空时路由到对应 AgentInstance 执行
    /// - `subTask.delegatedTo` 非空时通过 AgentMessageBus 发送委派请求并等待结果
    /// - 两者均为空时回退到默认 executor 流程（向后兼容）
    /// - Throws: `OrchestratorError.noActiveTask` 或子任务执行错误
    func executeAll() async throws {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }

        // v1.1 Phase B: 设置委派监听器（在 dagEngine.run 之前启动，确保订阅就绪）
        let delegationListener = startDelegationListener()

        // v1.1 Phase B: 捕获 Agent 实例快照用于角色路由（@MainActor final class 为 Sendable）
        let agentInstancesSnapshot = self.agentInstances
        var roleMap: [AgentRole: AgentInstance] = [:]
        for instance in agentInstancesSnapshot.values {
            if roleMap[instance.role] == nil {
                roleMap[instance.role] = instance
            }
        }
        let bus = self.messageBus

        // Task 20: 委托给 DAGExecutionEngine 并行调度
        let executor: DAGExecutionEngine.NodeExecutor = { [llmProvider, agentConfig, enableReview, maxReviewRetries] subTask in
            // executor 在非 MainActor 上下文执行（保证并行）
            // 仅捕获 Sendable 值：llmProvider / agentConfig / enableReview / maxReviewRetries / roleMap / bus

            // v1.1 Phase B: 优先处理委派（delegatedTo 非空）
            if let delegatedTo = subTask.delegatedTo {
                return try await Self.executeViaDelegation(
                    subTask: subTask,
                    delegatedTo: delegatedTo,
                    messageBus: bus
                )
            }

            // v1.1 Phase B: 角色路由（assignedRole 非空且有匹配 AgentInstance）
            if let role = subTask.assignedRole, let instance = roleMap[role] {
                let result = try await instance.execute(subTask: subTask, llmProvider: llmProvider)
                return result
            }

            // 默认 executor 流程（向后兼容）
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

            var result = ""
            let stream = llmProvider.chat(messages: messages, config: config, apiKey: "")
            for await chunk in stream {
                result += chunk
            }

            // 审查者角色审查结果（enableReview=true 时）
            if enableReview {
                var attempts = 0
                while attempts < maxReviewRetries {
                    let passed = await Self.reviewResult(subTask: subTask, result: result, llmProvider: llmProvider, model: model)
                    if passed { break }
                    attempts += 1
                    // 审查未通过，重新执行
                    let retryStream = llmProvider.chat(messages: messages, config: config, apiKey: "")
                    result = ""
                    for await chunk in retryStream {
                        result += chunk
                    }
                }
            }
            return result
        }

        do {
            try await dagEngine.run(task, executor: executor)
            // 所有节点终止后：若全部完成（含 skipped）则标记任务完成；若有 failed 则标记失败
            if task.isAllSubTasksCompleted {
                task.markCompleted()
            } else if task.hasFailedSubTask {
                task.markFailed()
            }
            try modelContext.save()
        } catch let error as DAGExecutionEngine.EngineError {
            // 引擎错误转换为 OrchestratorError
            switch error {
            case .deadlock:
                task.markFailed()
                try modelContext.save()
                throw OrchestratorError.noExecutableSubTask
            case .subTaskFailed(let id, let reason):
                task.markFailed()
                try modelContext.save()
                throw OrchestratorError.subTaskFailed(id, reason)
            case .stateMachine(let smError):
                throw OrchestratorError.subTaskFailed(UUID(), smError.localizedDescription)
            }
        }

        // v1.1 Phase B: 停止委派监听器
        delegationListener.cancel()
    }

    // MARK: - v1.1 Phase B: 委派监听与执行

    /// v1.1 Phase B: 启动委派监听器，处理来自其他 Agent 的任务委派请求。
    ///
    /// 监听 "delegation.requests" 主题，收到 taskDelegation 消息后：
    /// 1. 查找目标 AgentInstance
    /// 2. 从 currentTask 中查找 SubTask
    /// 3. 调用 AgentInstance.execute 执行
    /// 4. 通过 messageBus 发布 resultDelivery 回传结果
    ///
    /// 监听器在 executeAll 结束时被取消。
    /// - Returns: 监听器 Task（可取消）
    private func startDelegationListener() -> Task<Void, Never> {
        let bus = self.messageBus
        let llm = self.llmProvider

        // 先订阅再启动 Task，确保订阅就绪后才可能收到消息
        // subscribe 是 actor 方法，await 返回时订阅已注册
        let subscriptionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let stream = await bus.subscribe(topic: "delegation.requests")
            for await message in stream {
                guard Task.isCancelled == false else { break }
                await self.handleDelegationMessage(message, bus: bus, llmProvider: llm)
            }
        }
        return subscriptionTask
    }

    /// v1.1 Phase B: 处理单条委派消息
    ///
    /// 查找目标 Agent 与 SubTask，执行后将结果回传至 "delegation.result.<subTaskId>" 主题。
    /// - Parameters:
    ///   - message: 委派消息
    ///   - bus: 消息总线
    ///   - llmProvider: LLM 供应商
    private func handleDelegationMessage(_ message: AgentMessage, bus: AgentMessageBus, llmProvider: LLMProvider) async {
        guard case .taskDelegation(let subTaskId, let from, let to, _) = message else { return }
        guard let instance = agentInstances[to] else {
            // 目标 Agent 不存在：回传错误结果
            await bus.publish(
                topic: "delegation.result.\(subTaskId)",
                message: .resultDelivery(subTaskId: subTaskId, from: to, to: from, result: "ERROR: 目标 Agent 不存在")
            )
            return
        }
        guard let task = currentTask,
              let sub = task.subTasks.first(where: { $0.id == subTaskId }) else {
            await bus.publish(
                topic: "delegation.result.\(subTaskId)",
                message: .resultDelivery(subTaskId: subTaskId, from: to, to: from, result: "ERROR: 子任务不存在")
            )
            return
        }

        do {
            let result = try await instance.execute(subTask: sub, llmProvider: llmProvider)
            await bus.publish(
                topic: "delegation.result.\(subTaskId)",
                message: .resultDelivery(subTaskId: subTaskId, from: to, to: from, result: result)
            )
        } catch {
            await bus.publish(
                topic: "delegation.result.\(subTaskId)",
                message: .resultDelivery(subTaskId: subTaskId, from: to, to: from, result: "ERROR: \(error.localizedDescription)")
            )
        }
    }

    /// v1.1 Phase B: 通过消息总线委派子任务执行。
    ///
    /// 流程：
    /// 1. 订阅结果主题 "delegation.result.<subTaskId>"（先订阅防丢失）
    /// 2. 发布委派请求到 "delegation.requests"
    /// 3. 等待结果回传（含 30s 超时保护）
    /// - Parameters:
    ///   - subTask: 待委派的子任务
    ///   - delegatedTo: 委派目标 Agent ID
    ///   - messageBus: 消息总线
    /// - Returns: 委派执行结果字符串
    /// - Throws: 委派超时或结果为空时抛出错误
    private static func executeViaDelegation(
        subTask: SubTask,
        delegatedTo: UUID,
        messageBus: AgentMessageBus
    ) async throws -> String {
        let resultTopic = "delegation.result.\(subTask.id)"

        // 1. 先订阅结果主题（防止结果在订阅前发布导致丢失）
        let resultStream = await messageBus.subscribe(topic: resultTopic)

        // 2. 发布委派请求
        await messageBus.publish(
            topic: "delegation.requests",
            message: .taskDelegation(
                subTaskId: subTask.id,
                from: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                to: delegatedTo,
                description: subTask.description
            )
        )

        // 3. 等待结果（30s 超时）
        let result: String? = await withTaskGroup(of: String?.self) { group in
            // 结果等待子任务
            group.addTask {
                for await msg in resultStream {
                    if case .resultDelivery(_, _, _, let r) = msg {
                        return r
                    }
                }
                return nil
            }
            // 超时子任务
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let finalResult = result, !finalResult.hasPrefix("ERROR:") else {
            throw AgentInstance.AgentInstanceError.emptyResponse
        }
        return finalResult
    }


    /// Task 20: 静态审查方法（不依赖 self，可在非 MainActor 上下文调用）
    /// - Parameters:
    ///   - subTask: 被审查的子任务
    ///   - result: 执行结果
    ///   - llmProvider: LLM 供应商
    ///   - model: 模型名
    /// - Returns: true 表示审查通过
    private static func reviewResult(subTask: SubTask, result: String, llmProvider: LLMProvider, model: String) async -> Bool {
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
        let config = ChatConfig(model: model, systemPrompt: systemPrompt, maxTokens: 512, temperature: 0.3)
        let stream = llmProvider.chat(messages: messages, config: config, apiKey: "")
        var response = ""
        for await chunk in stream {
            response += chunk
        }
        return response.contains("通过") && !response.contains("不通过")
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

    // MARK: - Task 20: 用户干预

    /// Task 20: 跳过失败节点（用户干预）
    ///
    /// 将指定 failed 节点状态改为 skipped，并级联跳过其下游依赖节点。
    /// - Parameter nodeID: 失败节点 ID
    /// - Throws: `OrchestratorError.noActiveTask`
    func skipFailedNode(nodeID: UUID) async throws {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }
        await dagEngine.skipFailedNode(task: task, nodeID: nodeID)
        try modelContext.save()
    }

    /// Task 20: 重试失败节点（用户干预）
    ///
    /// 重置失败节点为 pending，重新执行。
    /// - Parameter nodeID: 失败节点 ID
    /// - Throws: `OrchestratorError.noActiveTask` 或执行错误
    func retryFailedNode(nodeID: UUID) async throws {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }
        let executor: DAGExecutionEngine.NodeExecutor = { [llmProvider, agentConfig, enableReview, maxReviewRetries] subTask in
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
            var result = ""
            let stream = llmProvider.chat(messages: messages, config: config, apiKey: "")
            for await chunk in stream {
                result += chunk
            }
            if enableReview {
                var attempts = 0
                while attempts < maxReviewRetries {
                    let passed = await Self.reviewResult(subTask: subTask, result: result, llmProvider: llmProvider, model: model)
                    if passed { break }
                    attempts += 1
                    let retryStream = llmProvider.chat(messages: messages, config: config, apiKey: "")
                    result = ""
                    for await chunk in retryStream {
                        result += chunk
                    }
                }
            }
            return result
        }
        try await dagEngine.retryFailedNode(task: task, nodeID: nodeID, executor: executor)
        try modelContext.save()
    }

    /// Task 20: 取消整个任务（用户干预）
    ///
    /// 将所有 pending/running 节点标记为 skipped，任务状态改为 cancelled。
    /// - Throws: `OrchestratorError.noActiveTask`
    func cancelTaskIntervention() async throws {
        guard let task = currentTask else {
            throw OrchestratorError.noActiveTask
        }
        await dagEngine.cancelTask(task)
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
            // P2-3: 携带 underlying 保留原始 Error 上下文
            throw OrchestratorError.subTaskFailedWithCause(id: subTask.id, reason: error.localizedDescription, underlying: error)
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
    /// Task 20 扩展：加载检查点，从最后一个 `completed` 节点续执行。
    /// 幂等恢复：检查点中已记录的 completed 节点 ID 集合，不重复执行。
    ///
    /// 流程：
    /// 1. 查找 status == .inProgress 的 AgentTask
    /// 2. 若存在检查点（checkpointAt != nil），验证 completedNodeIDs 与 subTasks 状态一致
    /// 3. 设为当前任务，等待 executeAll() 调用续执行
    private func resumeInProgressTask() throws {
        let descriptor = FetchDescriptor<AgentTask>()
        let tasks = try modelContext.fetch(descriptor)
        if let inProgressTask = tasks.first(where: { $0.status == .inProgress }) {
            currentTask = inProgressTask
            // Task 20: 加载检查点，验证已完成节点状态
            loadCheckpointForResume(task: inProgressTask)
        }
    }

    /// Task 20: 加载检查点进行幂等恢复
    ///
    /// 将 completedNodeIDs 中记录的节点状态同步到 subTasks（防止数据不一致）。
    /// - Parameter task: 待恢复的任务
    private func loadCheckpointForResume(task: AgentTask) {
        guard task.checkpointAt != nil else { return }
        let completedSet = Set(task.completedNodeIDs)
        // 验证：检查点中标记为 completed 的节点，subTasks 中也应为 completed
        for sub in task.subTasks where completedSet.contains(sub.id) {
            if sub.status != .completed && sub.status != .skipped {
                // 数据不一致：检查点标记完成但 subTask 状态未更新，修正为 completed
                _ = task.updateSubTaskStatus(id: sub.id, status: .completed)
            }
        }
    }
}
