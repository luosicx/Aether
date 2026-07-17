import XCTest
import SwiftData
@testable import Aether

/// Task 20 阶段 3: CheckpointManager 单元测试
///
/// 覆盖：
/// - 初始化（默认/带 modelContext）
/// - checkpoint() 更新 task.checkpointAt 与 completedNodeIDs
/// - 节流保存（500ms 间隔内不重复保存）
/// - flush() 强制立即保存
/// - loadCheckpoint() 读取已完成节点 ID 集合
/// - hasCheckpoint() / checkpointTimestamp()
/// - pendingChanges 节流期间变更标志
/// - reset() 重置节流状态
/// - 集成 NodeStateMachine 验证快照读取
@MainActor
final class CheckpointManagerTests: XCTestCase {

    // MARK: - 测试夹具

    /// 创建内存中的 ModelContext（用于测试实际持久化路径）
    /// - Returns: 内存 ModelContext
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AgentTask.self, configurations: config)
        return ModelContext(container)
    }

    /// 创建测试用 AgentTask
    /// - Parameter subTaskCount: 子任务数量
    /// - Returns: 包含指定数量子任务的 AgentTask
    private func makeTask(subTaskCount: Int = 3) -> AgentTask {
        let task = AgentTask(goal: "测试目标")
        let subs = (0..<subTaskCount).map { SubTask(title: "子任务\($0)", order: $0) }
        task.updateSubTasks(subs)
        return task
    }

    /// 创建并填充 NodeStateMachine
    /// - Parameters:
    ///   - task: 提供节点 ID
    ///   - completedIndices: 已完成的子任务索引列表
    /// - Returns: 配置好的状态机
    private func makeStateMachine(task: AgentTask, completedIndices: [Int] = []) async -> NodeStateMachine {
        let nodeIDs = task.subTasks.map(\.id)
        let sm = NodeStateMachine(nodeIDs: nodeIDs)
        for idx in completedIndices {
            let id = task.subTasks[idx].id
            try? await sm.markRunning(id)
            try? await sm.markCompleted(id)
            _ = task.updateSubTaskStatus(id: id, status: .completed)
        }
        return sm
    }

    // MARK: - 初始化

    /// 默认初始化：无 modelContext（通过 pendingChanges 间接验证初始化成功）
    func testInitDefault() {
        let manager = CheckpointManager()
        XCTAssertFalse(manager.pendingChanges, "初始应无待保存变更")
    }

    /// 带 modelContext 初始化：通过实际 checkpoint 持久化路径验证注入成功
    func testInitWithContext() throws {
        let context = try makeContext()
        let manager = CheckpointManager(modelContext: context)
        // 注入后应能正常调用 checkpoint 不崩溃
        let task = makeTask(subTaskCount: 1)
        context.insert(task)
        let sm = NodeStateMachine(nodeIDs: task.subTasks.map(\.id))
        let exp = expectation(description: "checkpoint completes")
        Task { @MainActor in
            await manager.checkpoint(task: task, stateMachine: sm)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        XCTAssertNotNil(task.checkpointAt, "注入 modelContext 后应能完成 checkpoint")
    }

    // MARK: - checkpoint()

    /// checkpoint() 应更新 task.checkpointAt 与 completedNodeIDs
    func testCheckpointUpdatesTaskFields() async throws {
        let task = makeTask(subTaskCount: 3)
        let sm = await makeStateMachine(task: task, completedIndices: [0, 1])
        let manager = CheckpointManager(modelContext: nil)

        XCTAssertNil(task.checkpointAt, "初始 checkpointAt 应为 nil")
        XCTAssertTrue(task.completedNodeIDs.isEmpty, "初始 completedNodeIDs 应为空")

        await manager.checkpoint(task: task, stateMachine: sm)

        XCTAssertNotNil(task.checkpointAt, "checkpoint 后 checkpointAt 应非 nil")
        XCTAssertEqual(task.completedNodeIDs.count, 2, "应记录 2 个已完成节点")
        XCTAssertTrue(task.completedNodeIDs.contains(task.subTasks[0].id))
        XCTAssertTrue(task.completedNodeIDs.contains(task.subTasks[1].id))
        XCTAssertFalse(task.completedNodeIDs.contains(task.subTasks[2].id))
    }

    /// checkpoint() 包含 skipped 节点
    func testCheckpointIncludesSkippedNodes() async throws {
        let task = makeTask(subTaskCount: 3)
        let sm = NodeStateMachine(nodeIDs: task.subTasks.map(\.id))
        // 标记 s0 完成，s1 跳过
        try? await sm.markRunning(task.subTasks[0].id)
        try? await sm.markCompleted(task.subTasks[0].id)
        try? await sm.markSkipped(task.subTasks[1].id)
        _ = task.updateSubTaskStatus(id: task.subTasks[0].id, status: .completed)
        _ = task.updateSubTaskStatus(id: task.subTasks[1].id, status: .skipped)

        let manager = CheckpointManager(modelContext: nil)
        await manager.checkpoint(task: task, stateMachine: sm)

        XCTAssertEqual(task.completedNodeIDs.count, 2, "应包含 completed + skipped 节点")
        XCTAssertTrue(task.completedNodeIDs.contains(task.subTasks[0].id))
        XCTAssertTrue(task.completedNodeIDs.contains(task.subTasks[1].id))
    }

    /// 空状态机：checkpoint 后 completedNodeIDs 为空但 checkpointAt 非 nil
    func testCheckpointWithEmptyStateMachine() async {
        let task = makeTask(subTaskCount: 0)
        let sm = NodeStateMachine()
        let manager = CheckpointManager(modelContext: nil)

        await manager.checkpoint(task: task, stateMachine: sm)

        XCTAssertNotNil(task.checkpointAt)
        XCTAssertTrue(task.completedNodeIDs.isEmpty)
    }

    // MARK: - 节流保存

    /// 节流：500ms 内多次 checkpoint 只保存一次（pendingChanges 标志切换）
    func testThrottleWithinInterval() async throws {
        let task = makeTask(subTaskCount: 1)
        let sm = await makeStateMachine(task: task, completedIndices: [0])
        let manager = CheckpointManager(modelContext: nil)

        // 第一次：立即保存
        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertFalse(manager.pendingChanges, "首次 checkpoint 应立即保存，无 pending")

        // 第二次（立即）：应节流，标记 pending
        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertTrue(manager.pendingChanges, "节流期间应标记 pendingChanges")
    }

    /// 节流：超过 500ms 后再次 checkpoint 应立即保存
    func testThrottleAfterInterval() async throws {
        let task = makeTask(subTaskCount: 1)
        let sm = await makeStateMachine(task: task, completedIndices: [0])
        let manager = CheckpointManager(modelContext: nil)

        // 第一次：立即保存
        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertFalse(manager.pendingChanges)

        // 等待 600ms（超过 500ms 节流间隔）
        try? await Task.sleep(nanoseconds: 600_000_000)

        // 第二次：应立即保存
        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertFalse(manager.pendingChanges, "超过节流间隔后应立即保存")
    }

    /// throttleInterval 常量应为 0.5s
    func testThrottleIntervalConstant() {
        XCTAssertEqual(CheckpointManager.throttleInterval, 0.5, "节流间隔应为 500ms")
    }

    // MARK: - flush()

    /// flush() 强制立即保存并清除 pendingChanges
    func testFlushForcesImmediateSave() async throws {
        let task = makeTask(subTaskCount: 1)
        let sm = await makeStateMachine(task: task, completedIndices: [0])
        let manager = CheckpointManager(modelContext: nil)

        // 第一次 checkpoint（立即保存）
        await manager.checkpoint(task: task, stateMachine: sm)
        // 第二次（节流，标记 pending）
        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertTrue(manager.pendingChanges)

        // flush 强制保存
        manager.flush(task: task)
        XCTAssertFalse(manager.pendingChanges, "flush 后应清除 pendingChanges")
    }

    /// flush() 即使无 pending 也能正常调用
    func testFlushWithNoPending() {
        let task = makeTask(subTaskCount: 1)
        let manager = CheckpointManager(modelContext: nil)
        // 初始无 pending，flush 不应崩溃
        manager.flush(task: task)
        XCTAssertFalse(manager.pendingChanges)
    }

    // MARK: - loadCheckpoint()

    /// loadCheckpoint() 返回 task.completedNodeIDs 的 Set 形式
    func testLoadCheckpointReturnsSet() async throws {
        let task = makeTask(subTaskCount: 3)
        let sm = await makeStateMachine(task: task, completedIndices: [0, 2])
        let manager = CheckpointManager(modelContext: nil)

        await manager.checkpoint(task: task, stateMachine: sm)
        let loaded = manager.loadCheckpoint(task: task)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.contains(task.subTasks[0].id))
        XCTAssertTrue(loaded.contains(task.subTasks[2].id))
        XCTAssertFalse(loaded.contains(task.subTasks[1].id))
    }

    /// loadCheckpoint() 未 checkpoint 时返回空集合
    func testLoadCheckpointEmptyWhenNoCheckpoint() {
        let task = makeTask(subTaskCount: 2)
        let manager = CheckpointManager(modelContext: nil)
        let loaded = manager.loadCheckpoint(task: task)
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - hasCheckpoint / checkpointTimestamp

    /// hasCheckpoint：未 checkpoint 时为 false
    func testHasCheckpointFalseInitially() {
        let task = makeTask(subTaskCount: 1)
        let manager = CheckpointManager(modelContext: nil)
        XCTAssertFalse(manager.hasCheckpoint(task))
    }

    /// hasCheckpoint：checkpoint 后为 true
    func testHasCheckpointTrueAfterCheckpoint() async throws {
        let task = makeTask(subTaskCount: 1)
        let sm = await makeStateMachine(task: task)
        let manager = CheckpointManager(modelContext: nil)

        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertTrue(manager.hasCheckpoint(task))
    }

    /// checkpointTimestamp：未 checkpoint 时为 nil
    func testCheckpointTimestampNilInitially() {
        let task = makeTask(subTaskCount: 1)
        let manager = CheckpointManager(modelContext: nil)
        XCTAssertNil(manager.checkpointTimestamp(task))
    }

    /// checkpointTimestamp：checkpoint 后返回时间戳
    func testCheckpointTimestampReturnsValue() async throws {
        let task = makeTask(subTaskCount: 1)
        let sm = await makeStateMachine(task: task)
        let manager = CheckpointManager(modelContext: nil)

        let before = Date()
        await manager.checkpoint(task: task, stateMachine: sm)
        let after = Date()

        let timestamp = manager.checkpointTimestamp(task)
        XCTAssertNotNil(timestamp)
        if let ts = timestamp {
            XCTAssertGreaterThanOrEqual(ts, before)
            XCTAssertLessThanOrEqual(ts, after)
        }
    }

    // MARK: - reset()

    /// reset() 清除节流状态
    func testResetClearsThrottleState() async throws {
        let task = makeTask(subTaskCount: 1)
        let sm = await makeStateMachine(task: task, completedIndices: [0])
        let manager = CheckpointManager(modelContext: nil)

        await manager.checkpoint(task: task, stateMachine: sm)
        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertTrue(manager.pendingChanges)

        manager.reset()
        XCTAssertFalse(manager.pendingChanges, "reset 后应清除 pendingChanges")
    }

    /// reset() 后下次 checkpoint 应立即保存（不再节流）
    func testResetAllowsImmediateSave() async throws {
        let task = makeTask(subTaskCount: 1)
        let sm = await makeStateMachine(task: task, completedIndices: [0])
        let manager = CheckpointManager(modelContext: nil)

        await manager.checkpoint(task: task, stateMachine: sm)
        await manager.checkpoint(task: task, stateMachine: sm)
        manager.reset()

        // reset 后再次 checkpoint 应立即保存（无 pending）
        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertFalse(manager.pendingChanges)
    }

    // MARK: - 集成持久化（in-memory ModelContext）

    /// 带 modelContext 的 checkpoint 应能成功保存而不崩溃
    func testCheckpointWithContextPersistsSuccessfully() async throws {
        let context = try makeContext()
        let task = makeTask(subTaskCount: 2)
        context.insert(task)

        let sm = await makeStateMachine(task: task, completedIndices: [0])
        let manager = CheckpointManager(modelContext: context)

        await manager.checkpoint(task: task, stateMachine: sm)
        XCTAssertNotNil(task.checkpointAt)

        // flush 强制保存
        manager.flush(task: task)

        // 从 context 查询验证
        let descriptor = FetchDescriptor<AgentTask>()
        let tasks = try context.fetch(descriptor)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.id, task.id)
        XCTAssertNotNil(tasks.first?.checkpointAt)
    }

    /// 多次 checkpoint + flush 后数据一致
    func testMultipleCheckpointsConsistency() async throws {
        let context = try makeContext()
        let task = makeTask(subTaskCount: 3)
        context.insert(task)

        let sm = NodeStateMachine(nodeIDs: task.subTasks.map(\.id))
        let manager = CheckpointManager(modelContext: context)

        // 完成 s0
        try? await sm.markRunning(task.subTasks[0].id)
        try? await sm.markCompleted(task.subTasks[0].id)
        _ = task.updateSubTaskStatus(id: task.subTasks[0].id, status: .completed)
        await manager.checkpoint(task: task, stateMachine: sm)

        // 完成 s1
        try? await sm.markRunning(task.subTasks[1].id)
        try? await sm.markCompleted(task.subTasks[1].id)
        _ = task.updateSubTaskStatus(id: task.subTasks[1].id, status: .completed)
        await manager.checkpoint(task: task, stateMachine: sm)
        manager.flush(task: task)

        XCTAssertEqual(task.completedNodeIDs.count, 2)
        XCTAssertTrue(task.completedNodeIDs.contains(task.subTasks[0].id))
        XCTAssertTrue(task.completedNodeIDs.contains(task.subTasks[1].id))
    }

    // MARK: - 幂等恢复场景

    /// 模拟恢复：加载已有检查点后，引擎应跳过已完成节点
    func testCheckpointSupportsIdempotentResume() async throws {
        let task = makeTask(subTaskCount: 3)
        let sm = await makeStateMachine(task: task, completedIndices: [0])
        let manager = CheckpointManager(modelContext: nil)

        // 第一次 checkpoint：记录 s0 已完成
        await manager.checkpoint(task: task, stateMachine: sm)
        let firstSnapshot = manager.loadCheckpoint(task: task)
        XCTAssertEqual(firstSnapshot.count, 1)

        // 模拟重启：重新加载检查点
        let loaded = manager.loadCheckpoint(task: task)
        XCTAssertEqual(loaded, firstSnapshot, "重载检查点应一致")

        // 模拟引擎恢复：s0 应被跳过（已 completed）
        XCTAssertEqual(task.subTasks[0].status, .completed)
        // 引擎通过 nextExecutableSubTasks() 应只返回 s1（s2 依赖 s1）
        let executable = task.nextExecutableSubTasks()
        XCTAssertEqual(executable.count, 1)
        XCTAssertEqual(executable.first?.id, task.subTasks[1].id)
    }
}
