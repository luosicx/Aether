import Foundation
import SwiftData
import AetherFoundation

/// Task 20 阶段 2: 并行 DAG 执行引擎。
///
/// 职责：
/// - 获取所有 `dependencies` 均为 `completed`/`skipped` 的 `pending` 节点
/// - 使用 `TaskGroup` 并行提交执行（最大并发 4，通过 semaphore 控制）
/// - 通过 `NodeStateMachine`（actor）管理状态迁移
/// - 通过 `ToolExecutionCoordinator`（actor）串行化工具调用
/// - 跳过 failed 节点的下游依赖（自动级联 skipped）
/// - 提供进度回调（@MainActor 闭包）
///
/// 与 `AgentOrchestrator` 关系：
/// - `AgentOrchestrator.executeAll()` 内部委托给 `DAGExecutionEngine.run(_:)`
/// - 引擎不持有 `currentTask`，由 orchestrator 注入
/// - 引擎对外接口为 `run(_:)`，不暴露内部状态
@MainActor
final class DAGExecutionEngine {

    /// 引擎错误
    enum EngineError: Error, LocalizedError {
        /// 节点状态机错误（透传）
        case stateMachine(NodeStateMachine.StateMachineError)
        /// 子任务执行失败（携带 ID 与原因）
        case subTaskFailed(UUID, String)
        /// DAG 中存在无法推进的死锁（节点 pending 但所有依赖都无法完成）
        case deadlock([UUID])

        var errorDescription: String? {
            switch self {
            case .stateMachine(let error):
                return error.localizedDescription
            case .subTaskFailed(let id, let reason):
                return "子任务 \(id) 执行失败：\(reason)"
            case .deadlock(let ids):
                return "DAG 死锁，无法推进节点：\(ids)"
            }
        }
    }

    /// 用户干预动作
    enum InterventionAction {
        /// 跳过失败节点（状态变 skipped，下游依赖自动 skipped）
        case skip
        /// 重试失败节点（重置为 pending，重新执行）
        case retry
        /// 取消整个任务
        case cancel
    }

    /// 最大并发数
    static let maxConcurrency = 4

    /// 节点状态机（actor，线程安全）
    private let stateMachine: NodeStateMachine
    /// 工具执行协调器（actor，串行化工具调用）
    private let toolCoordinator: ToolExecutionCoordinator
    /// 重试策略
    private let retryPolicy: RetryPolicy
    /// 检查点管理器
    private let checkpointManager: CheckpointManager

    /// 节点执行器闭包（由 AgentOrchestrator 注入，避免直接依赖 LLMProvider）
    /// - Parameter subTask: 待执行的子任务
    /// - Returns: 执行结果字符串
    typealias NodeExecutor = @Sendable (SubTask) async throws -> String

    /// 进度回调（主线程）
    var onProgress: ((AgentTask) -> Void)?
    /// 节点失败回调（触发用户干预 UI）
    var onNodeFailed: ((SubTask) -> Void)?
    /// 节点完成回调
    var onNodeCompleted: ((SubTask) -> Void)?

    /// 创建 DAGExecutionEngine
    /// - Parameters:
    ///   - stateMachine: 节点状态机（可选，默认新建）
    ///   - toolCoordinator: 工具协调器（可选，默认 shared）
    ///   - retryPolicy: 重试策略（可选，默认 `.default`）
    ///   - checkpointManager: 检查点管理器（可选，默认新建）
    init(stateMachine: NodeStateMachine? = nil,
         toolCoordinator: ToolExecutionCoordinator = ToolExecutionCoordinator.shared,
         retryPolicy: RetryPolicy = .default,
         checkpointManager: CheckpointManager? = nil) {
        self.stateMachine = stateMachine ?? NodeStateMachine()
        self.toolCoordinator = toolCoordinator
        self.retryPolicy = retryPolicy
        self.checkpointManager = checkpointManager ?? CheckpointManager()
    }

    /// 执行 AgentTask 的全部子任务（DAG 并行调度）
    ///
    /// 流程：
    /// 1. 注册所有节点到状态机
    /// 2. 循环：获取所有可执行 pending 节点 → 并行执行 → 更新状态 → 检查点
    /// 3. 直到所有节点终止或遇到失败需要干预
    /// - Parameters:
    ///   - task: 待执行的 AgentTask
    ///   - executor: 节点执行器闭包（由 orchestrator 注入）
    /// - Throws: `EngineError`
    func run(_ task: AgentTask, executor: @escaping @Sendable NodeExecutor) async throws {
        let subTasks = task.subTasks
        guard !subTasks.isEmpty else { return }

        // 1. 注册所有节点到状态机（同步当前持久化状态）
        let nodeIDs = subTasks.map(\.id)
        await stateMachine.register(nodeIDs: nodeIDs)
        // 同步已有状态：根据持久化状态覆盖状态机（幂等恢复）
        for sub in subTasks {
            switch sub.status {
            case .completed:
                await stateMachine.override(nodeID: sub.id, status: .completed)
            case .skipped:
                await stateMachine.override(nodeID: sub.id, status: .skipped)
            case .failed:
                await stateMachine.override(nodeID: sub.id, status: .failed)
            case .inProgress:
                // 重新执行 inProgress 节点
                await stateMachine.override(nodeID: sub.id, status: .pending)
            case .pending:
                // 保持 pending
                break
            }
        }

        // 2. 循环调度
        while !(await stateMachine.isAllTerminal()) {
            // 检测死锁：是否有 pending 节点但都无法执行
            let pendingIDs = await stateMachine.nodeIDs(in: .pending)
            if pendingIDs.isEmpty {
                // 无 pending 节点但未全部终止：可能存在 running，等待
                let runningIDs = await stateMachine.nodeIDs(in: .inProgress)
                if runningIDs.isEmpty {
                    // 既无 pending 也无 running 但未终止：理论上不应发生
                    break
                }
                // 等待 running 节点完成（轮询间隔）
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                continue
            }

            // 获取可执行节点（依赖全部为 completed/skipped）
            let executable = task.nextExecutableSubTasks()
            if executable.isEmpty {
                // 有 pending 但无可执行：可能依赖中有 failed 节点 → 级联 skipped
                let progressed = await cascadeSkipFailed(task: task)
                if !progressed {
                    // 无 failed 节点级联，但仍无可执行 → 死锁
                    let stuckIDs = pendingIDs
                    throw EngineError.deadlock(stuckIDs)
                }
                continue
            }

            // 3. 并行执行（最大并发 4）
            try await executeBatch(executable, task: task, executor: executor)

            // 4. 检查点保存
            await checkpointManager.checkpoint(task: task, stateMachine: stateMachine)

            // 5. 进度回调
            onProgress?(task)
        }

        // 最终检查点
        await checkpointManager.checkpoint(task: task, stateMachine: stateMachine)
        onProgress?(task)
    }

    /// 并行执行一批可执行节点（最大并发 4）
    /// - Parameters:
    ///   - batch: 可执行子任务列表
    ///   - task: 所属 AgentTask
    ///   - executor: 节点执行器
    private func executeBatch(_ batch: [SubTask], task: AgentTask, executor: @escaping @Sendable NodeExecutor) async throws {
        // 限制并发数：取前 maxConcurrency 个
        let currentBatch = Array(batch.prefix(Self.maxConcurrency))
        let remaining = batch.dropFirst(Self.maxConcurrency)

        // 标记为 running
        for sub in currentBatch {
            _ = task.updateSubTaskStatus(id: sub.id, status: .inProgress)
            try await stateMachine.markRunning(sub.id)
        }
        onProgress?(task)

        // 捕获 Sendable 依赖到本地常量（避免在 TaskGroup 子任务中跨 MainActor 访问 self）
        let retryPolicy = self.retryPolicy
        let toolCoordinator = self.toolCoordinator
        let executorWrapper = executor

        // 并行执行（TaskGroup + semaphore）
        try await withThrowingTaskGroup(of: SubTaskResult.self) { group in
            for sub in currentBatch {
                group.addTask {
                    // 在子任务中本地执行重试逻辑，避免 MainActor 跳转
                    var lastError: Error?
                    for attempt in 0..<retryPolicy.maxAttempts {
                        do {
                            if let toolName = sub.toolName {
                                let toolResult = try await toolCoordinator.execute(name: toolName, arguments: [:])
                                return SubTaskResult(id: sub.id, result: toolResult, errorMessage: nil)
                            } else {
                                let execResult = try await executorWrapper(sub)
                                return SubTaskResult(id: sub.id, result: execResult, errorMessage: nil)
                            }
                        } catch {
                            lastError = error
                            let delay = retryPolicy.delay(forAttempt: attempt)
                            if delay > 0 {
                                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            }
                        }
                    }
                    let message = lastError?.localizedDescription ?? "重试用尽"
                    return SubTaskResult(id: sub.id, result: nil, errorMessage: message)
                }
            }
            // 收集结果
            for try await result in group {
                if let errorMessage = result.errorMessage {
                    // 标记失败
                    _ = task.updateSubTaskStatus(id: result.id, status: .failed, result: errorMessage)
                    try await stateMachine.markFailed(result.id)
                    if let failedSub = task.subTasks.first(where: { $0.id == result.id }) {
                        onNodeFailed?(failedSub)
                    }
                } else {
                    // 标记完成
                    _ = task.updateSubTaskStatus(id: result.id, status: .completed, result: result.result)
                    try await stateMachine.markCompleted(result.id)
                    if let completedSub = task.subTasks.first(where: { $0.id == result.id }) {
                        onNodeCompleted?(completedSub)
                    }
                }
            }
        }

        // 处理剩余节点（递归批次）
        if !remaining.isEmpty {
            try await executeBatch(Array(remaining), task: task, executor: executor)
        }
    }

    /// 级联跳过 failed 节点的下游依赖
    ///
    /// 当某节点 failed 后，依赖它的 pending 节点应自动 skipped。
    /// - Parameter task: 所属 AgentTask
    /// - Returns: 是否有节点被跳过（true 表示有进展）
    private func cascadeSkipFailed(task: AgentTask) async -> Bool {
        let failedIDs = Set(task.subTasks.filter { $0.status == .failed }.map(\.id))
        guard !failedIDs.isEmpty else { return false }

        var progressed = false
        for sub in task.subTasks where sub.status == .pending {
            // 若依赖中包含 failed 节点，标记为 skipped
            if !Set(sub.dependencies).isDisjoint(with: failedIDs) {
                _ = task.updateSubTaskStatus(id: sub.id, status: .skipped, result: "依赖节点失败，自动跳过")
                try? await stateMachine.markSkipped(sub.id)
                progressed = true
            }
        }
        return progressed
    }

    /// 用户干预：跳过失败节点
    /// - Parameter task: 所属 AgentTask
    /// - Parameter nodeID: 失败节点 ID
    func skipFailedNode(task: AgentTask, nodeID: UUID) async {
        _ = task.updateSubTaskStatus(id: nodeID, status: .skipped, result: "用户跳过")
        try? await stateMachine.markSkipped(nodeID)
        // 级联跳过下游依赖
        _ = await cascadeSkipFailed(task: task)
        await checkpointManager.checkpoint(task: task, stateMachine: stateMachine)
        onProgress?(task)
    }

    /// 用户干预：重试失败节点
    /// - Parameters:
    ///   - task: 所属 AgentTask
    ///   - nodeID: 失败节点 ID
    ///   - executor: 节点执行器
    func retryFailedNode(task: AgentTask, nodeID: UUID, executor: @escaping @Sendable NodeExecutor) async throws {
        guard let sub = task.subTasks.first(where: { $0.id == nodeID }) else { return }
        _ = task.updateSubTaskStatus(id: nodeID, status: .pending)
        await stateMachine.reset(nodeID)
        try await executeBatch([sub], task: task, executor: executor)
        await checkpointManager.checkpoint(task: task, stateMachine: stateMachine)
        onProgress?(task)
    }

    /// 用户干预：取消整个任务
    /// - Parameter task: 所属 AgentTask
    func cancelTask(_ task: AgentTask) async {
        // 将所有 pending/running 节点标记为 skipped
        for sub in task.subTasks where sub.status == .pending || sub.status == .inProgress {
            _ = task.updateSubTaskStatus(id: sub.id, status: .skipped, result: "任务取消")
            try? await stateMachine.markSkipped(sub.id)
        }
        task.cancel()
        await checkpointManager.checkpoint(task: task, stateMachine: stateMachine)
        onProgress?(task)
    }

    // MARK: - 私有辅助

    /// 直接覆盖节点状态（绕过状态机迁移校验，用于初始化恢复）
    private func overrideStatus(_ nodeID: UUID, _ status: SubTaskStatus) async {
        // 通过 reset + 对应 mark 实现（mark 要求特定前置状态，这里通过 reset 后再标记）
        // 但 markRunning/markCompleted 都需要特定前置，直接重置为 pending 后无法直接到 completed
        // 因此这里直接调用 markSkipped/markCompleted 的内部逻辑：先 reset 再覆盖
        // 由于 NodeStateMachine 的 statuses 是 private，我们扩展一个 override 方法
        await stateMachine.override(nodeID: nodeID, status: status)
    }
}

/// Task 20 阶段 2: 子任务执行结果（内部传输，Sendable）
private struct SubTaskResult: Sendable {
    let id: UUID
    let result: String?
    let errorMessage: String?
}
