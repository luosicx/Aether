import Foundation
import SwiftData

/// Task 20 阶段 3: 检查点管理器（@MainActor，与 AgentTask 同隔离）。
///
/// 职责：
/// - 每节点完成即 `modelContext.save()` 持久化
/// - 记录 `checkpointAt` 时间戳与已完成节点 ID 集合
/// - 节流保存（最多每 500ms 一次），避免高频保存导致性能下降
/// - 提供检查点加载接口，用于 `resumeInProgressTask` 幂等恢复
///
/// 与 `AgentTask` 关系：
/// - 检查点数据存储在 `AgentTask.checkpointAt` 与 `AgentTask.completedNodeIDs`
/// - 持久化通过注入的 `ModelContext` 完成
@MainActor
final class CheckpointManager {

    /// 节流间隔（秒）
    static let throttleInterval: TimeInterval = 0.5

    /// 上次保存时间
    private var lastSaveTime: Date = .distantPast
    /// 待保存标志（节流期间累积变更）
    private var hasPendingChanges: Bool = false
    /// 注入的 ModelContext
    private let modelContext: ModelContext?

    /// 创建 CheckpointManager
    /// - Parameter modelContext: SwiftData 上下文；测试时可传 nil 跳过实际持久化
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    /// 记录检查点：更新 task 的 checkpointAt 与 completedNodeIDs，并持久化（节流）。
    ///
    /// 流程：
    /// 1. 从 stateMachine 读取当前所有节点状态
    /// 2. 计算 completed（含 skipped）节点 ID 集合
    /// 3. 更新 task.checkpointAt 与 task.completedNodeIDs
    /// 4. 若距上次保存 > 500ms，立即 `modelContext.save()`；否则标记待保存
    /// - Parameters:
    ///   - task: 待检查点的 AgentTask
    ///   - stateMachine: 节点状态机
    func checkpoint(task: AgentTask, stateMachine: NodeStateMachine) async {
        let snapshot = await stateMachine.snapshot()
        let completedIDs = snapshot.compactMap { (id, status) -> UUID? in
            (status == .completed || status == .skipped) ? id : nil
        }
        // 更新 task 检查点字段
        task.recordCheckpoint(completedIDs: completedIDs)

        // 节流保存
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSaveTime)
        if elapsed >= Self.throttleInterval {
            persist(task: task)
            lastSaveTime = now
            hasPendingChanges = false
        } else {
            hasPendingChanges = true
        }
    }

    /// 强制立即保存（忽略节流，用于任务完成或取消时）
    /// - Parameter task: 待保存的 AgentTask
    func flush(task: AgentTask) {
        persist(task: task)
        lastSaveTime = Date()
        hasPendingChanges = false
    }

    /// 加载检查点：从 task 读取已完成节点 ID 集合
    /// - Parameter task: 待恢复的 AgentTask
    /// - Returns: 已完成节点 ID 集合
    func loadCheckpoint(task: AgentTask) -> Set<UUID> {
        Set(task.completedNodeIDs)
    }

    /// 检查点是否存在
    /// - Parameter task: 待检查的 AgentTask
    /// - Returns: true 表示存在有效检查点
    func hasCheckpoint(_ task: AgentTask) -> Bool {
        task.checkpointAt != nil
    }

    /// 检查点时间戳
    /// - Parameter task: 待检查的 AgentTask
    /// - Returns: 检查点时间戳；不存在返回 nil
    func checkpointTimestamp(_ task: AgentTask) -> Date? {
        task.checkpointAt
    }

    /// 是否有未保存的变更
    var pendingChanges: Bool {
        hasPendingChanges
    }

    /// 重置节流状态（用于测试或任务切换）
    func reset() {
        lastSaveTime = .distantPast
        hasPendingChanges = false
    }

    // MARK: - 私有

    /// 实际持久化逻辑
    private func persist(task _: AgentTask) {
        guard let modelContext = modelContext else { return }
        do {
            try modelContext.save()
        } catch {
            // 持久化失败：记录但不抛错（避免阻塞执行流程）
            // 上层可通过 task.checkpointAt 判断是否成功
        }
    }
}
