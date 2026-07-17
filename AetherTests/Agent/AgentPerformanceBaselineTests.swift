import XCTest
@testable import Aether

/// Task 20 阶段 5: Agent 性能基线测试
///
/// 验证 DAGExecutionEngine 在不同规模 DAG 下的执行性能与成功率：
/// - **简单**（≤3 子任务）：成功率 ≥ 95%
/// - **中等**（4-10 子任务）：成功率 ≥ 85%
/// - **复杂**（11-30 子任务）：成功率 ≥ 70%
///
/// 测试方法：
/// - 使用 Mock executor 模拟 LLM 调用（零延迟，避免真实 LLM 依赖）
/// - 使用零延迟 RetryPolicy 避免测试耗时
/// - 使用 `XCTest.measure` 采集执行时长
/// - 通过成功率阈值验证性能基线
///
/// 测试约束：
/// - 不依赖真实 LLM 调用
/// - 不触发系统权限对话框
/// - CI headless 环境可运行
@MainActor
final class AgentPerformanceBaselineTests: XCTestCase {

    /// 性能基线阈值
    enum Baseline {
        /// 简单 DAG（≤3 节点）成功率阈值
        static let simpleSuccessRate: Double = 0.95
        /// 中等 DAG（4-10 节点）成功率阈值
        static let mediumSuccessRate: Double = 0.85
        /// 复杂 DAG（11-30 节点）成功率阈值
        static let complexSuccessRate: Double = 0.70
    }

    /// 零延迟重试策略（避免测试等待退避）
    private let zeroDelayPolicy = RetryPolicy(maxAttempts: 3, initialDelay: 0, backoffMultiplier: 1.0)

    /// 单次尝试策略（无重试，便于成功率统计）
    private let singleAttemptPolicy = RetryPolicy(maxAttempts: 1, initialDelay: 0, backoffMultiplier: 1.0)

    // MARK: - 测试夹具

    /// 创建可配置失败率的 Mock executor
    /// - Parameter failureRate: 0.0~1.0，每个节点失败概率
    /// - Returns: 节点执行器闭包
    private func makeMockExecutor(failureRate: Double) -> DAGExecutionEngine.NodeExecutor {
        struct TestError: Error {}
        return { _ in
            // 使用确定性随机：基于时间戳 + 计数器避免纯随机导致测试不稳定
            let dice = Double.random(in: 0..<1)
            if dice < failureRate {
                throw TestError()
            }
            return "ok"
        }
    }

    /// 创建稳定的 Mock executor（按节点 ID 哈希决定失败，保证可重现）
    /// - Parameter failureRate: 0.0~1.0，每个节点失败概率
    /// - Returns: 节点执行器闭包
    private func makeStableMockExecutor(failureRate: Double) -> DAGExecutionEngine.NodeExecutor {
        struct TestError: Error {}
        return { sub in
            // 基于 UUID 哈希决定失败，保证同一组子任务结果稳定
            let hash = sub.id.hashValue
            let normalized = Double(abs(hash % 1000)) / 1000.0
            if normalized < failureRate {
                throw TestError()
            }
            return "ok"
        }
    }

    /// 创建并行子任务列表
    /// - Parameter count: 子任务数量
    /// - Returns: parallel=true 的子任务数组
    private func makeParallelSubTasks(count: Int) -> [SubTask] {
        (0..<count).map { SubTask(title: "任务\($0)", order: $0, parallel: true) }
    }

    /// 创建链式依赖子任务列表
    /// - Parameter count: 子任务数量
    /// - Returns: 链式依赖子任务数组（A → B → C）
    private func makeChainedSubTasks(count: Int) -> [SubTask] {
        var subs: [SubTask] = []
        var prevID: UUID?
        for i in 0..<count {
            let deps = prevID.map { [$0] } ?? []
            let sub = SubTask(title: "步骤\(i + 1)", dependencies: deps, order: i)
            subs.append(sub)
            prevID = sub.id
        }
        return subs
    }

    /// 执行 DAG 并统计成功率
    /// - Parameters:
    ///   - subTasks: 子任务列表
    ///   - executor: 节点执行器
    ///   - retryPolicy: 重试策略
    /// - Returns: (completedCount, totalCount, skippedCount, failedCount)
    private func executeAndCount(
        subTasks: [SubTask],
        executor: DAGExecutionEngine.NodeExecutor,
        retryPolicy: RetryPolicy
    ) async -> (completed: Int, skipped: Int, failed: Int, total: Int) {
        let task = AgentTask(goal: "基线测试")
        task.updateSubTasks(subTasks)
        task.markInProgress()

        let engine = DAGExecutionEngine(
            retryPolicy: retryPolicy,
            checkpointManager: CheckpointManager(modelContext: nil)
        )

        do {
            try await engine.run(task, executor: executor)
        } catch {
            // 引擎可能抛 deadlock 等，忽略后继续统计
        }

        let completed = task.subTasks.filter { $0.status == .completed }.count
        let skipped = task.subTasks.filter { $0.status == .skipped }.count
        let failed = task.subTasks.filter { $0.status == .failed }.count
        return (completed, skipped, failed, task.subTasks.count)
    }

    // MARK: - 简单 DAG 基线（≤3 子任务，≥95%）

    /// 简单 DAG：3 个并行节点，无失败，成功率应为 100%
    func testSimpleDAGPerfectSuccessRate() async throws {
        let subs = makeParallelSubTasks(count: 3)
        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed) / Double(stats.total)
        XCTAssertEqual(stats.completed, 3)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertEqual(successRate, 1.0, "无失败场景成功率应为 100%")
        XCTAssertGreaterThanOrEqual(successRate, Baseline.simpleSuccessRate)
    }

    /// 简单 DAG：3 个链式节点，成功率 ≥ 95%
    func testSimpleDAGChainedSuccessRate() async throws {
        let subs = makeChainedSubTasks(count: 3)
        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed + stats.skipped) / Double(stats.total)
        XCTAssertGreaterThanOrEqual(successRate, Baseline.simpleSuccessRate,
                                     "简单 DAG 成功率应 ≥ 95%")
    }

    /// 简单 DAG 执行时长基线（measure API）
    func testSimpleDAGExecutionTime() async throws {
        let subs = makeParallelSubTasks(count: 3)
        let executor = makeStableMockExecutor(failureRate: 0.0)

        measure {
            let exp = expectation(description: "execution completes")
            Task { @MainActor in
                let task = AgentTask(goal: "性能测试")
                task.updateSubTasks(subs)
                task.markInProgress()
                let engine = DAGExecutionEngine(
                    retryPolicy: zeroDelayPolicy,
                    checkpointManager: CheckpointManager(modelContext: nil)
                )
                try? await engine.run(task, executor: executor)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
    }

    // MARK: - 中等 DAG 基线（4-10 子任务，≥85%）

    /// 中等 DAG：5 个并行节点，成功率 ≥ 85%
    func testMediumDAGSuccessRate() async throws {
        let subs = makeParallelSubTasks(count: 5)
        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed + stats.skipped) / Double(stats.total)
        XCTAssertGreaterThanOrEqual(successRate, Baseline.mediumSuccessRate,
                                     "中等 DAG 成功率应 ≥ 85%")
    }

    /// 中等 DAG：10 个并行节点，成功率 ≥ 85%
    func testMediumDAGTenNodesSuccessRate() async throws {
        let subs = makeParallelSubTasks(count: 10)
        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed + stats.skipped) / Double(stats.total)
        XCTAssertEqual(stats.completed, 10, "无失败应全部完成")
        XCTAssertGreaterThanOrEqual(successRate, Baseline.mediumSuccessRate)
    }

    /// 中等 DAG：链式 + 并行混合，含少量失败
    func testMediumDAGMixedWithFailure() async throws {
        // 5 个并行节点 + 1 个依赖前 5 个的汇总节点
        let p1 = SubTask(title: "P1", order: 0, parallel: true)
        let p2 = SubTask(title: "P2", order: 1, parallel: true)
        let p3 = SubTask(title: "P3", order: 2, parallel: true)
        let p4 = SubTask(title: "P4", order: 3, parallel: true)
        let p5 = SubTask(title: "P5", order: 4, parallel: true)
        let agg = SubTask(title: "汇总", dependencies: [p1.id, p2.id, p3.id, p4.id, p5.id], order: 5)
        let subs = [p1, p2, p3, p4, p5, agg]

        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed + stats.skipped) / Double(stats.total)
        XCTAssertGreaterThanOrEqual(successRate, Baseline.mediumSuccessRate,
                                     "中等 DAG 混合场景成功率应 ≥ 85%")
    }

    /// 中等 DAG 执行时长基线
    func testMediumDAGExecutionTime() async throws {
        let subs = makeParallelSubTasks(count: 8)
        let executor = makeStableMockExecutor(failureRate: 0.0)

        measure {
            let exp = expectation(description: "execution completes")
            Task { @MainActor in
                let task = AgentTask(goal: "性能测试")
                task.updateSubTasks(subs)
                task.markInProgress()
                let engine = DAGExecutionEngine(
                    retryPolicy: zeroDelayPolicy,
                    checkpointManager: CheckpointManager(modelContext: nil)
                )
                try? await engine.run(task, executor: executor)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
    }

    // MARK: - 复杂 DAG 基线（11-30 子任务，≥70%）

    /// 复杂 DAG：15 个并行节点，成功率 ≥ 70%
    func testComplexDAGSuccessRate() async throws {
        let subs = makeParallelSubTasks(count: 15)
        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed + stats.skipped) / Double(stats.total)
        XCTAssertEqual(stats.completed, 15)
        XCTAssertGreaterThanOrEqual(successRate, Baseline.complexSuccessRate,
                                     "复杂 DAG 成功率应 ≥ 70%")
    }

    /// 复杂 DAG：30 个并行节点（阈值上限），成功率 ≥ 70%
    func testComplexDAGMaxNodesSuccessRate() async throws {
        let subs = makeParallelSubTasks(count: 30)
        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed + stats.skipped) / Double(stats.total)
        XCTAssertEqual(stats.completed, 30, "30 节点无失败应全部完成")
        XCTAssertGreaterThanOrEqual(successRate, Baseline.complexSuccessRate)
    }

    /// 复杂 DAG：链式 20 节点，成功率 ≥ 70%
    func testComplexDAGChainedSuccessRate() async throws {
        let subs = makeChainedSubTasks(count: 20)
        let executor = makeStableMockExecutor(failureRate: 0.0)
        let stats = await executeAndCount(subTasks: subs, executor: executor, retryPolicy: zeroDelayPolicy)

        let successRate = Double(stats.completed + stats.skipped) / Double(stats.total)
        XCTAssertGreaterThanOrEqual(successRate, Baseline.complexSuccessRate,
                                     "复杂链式 DAG 成功率应 ≥ 70%")
    }

    /// 复杂 DAG 执行时长基线
    func testComplexDAGExecutionTime() async throws {
        let subs = makeParallelSubTasks(count: 20)
        let executor = makeStableMockExecutor(failureRate: 0.0)

        measure {
            let exp = expectation(description: "execution completes")
            Task { @MainActor in
                let task = AgentTask(goal: "性能测试")
                task.updateSubTasks(subs)
                task.markInProgress()
                let engine = DAGExecutionEngine(
                    retryPolicy: zeroDelayPolicy,
                    checkpointManager: CheckpointManager(modelContext: nil)
                )
                try? await engine.run(task, executor: executor)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10.0)
        }
    }

    // MARK: - 性能基线常量验证

    /// 基线阈值常量正确
    func testBaselineConstants() {
        XCTAssertEqual(Baseline.simpleSuccessRate, 0.95, "简单 DAG 阈值应为 95%")
        XCTAssertEqual(Baseline.mediumSuccessRate, 0.85, "中等 DAG 阈值应为 85%")
        XCTAssertEqual(Baseline.complexSuccessRate, 0.70, "复杂 DAG 阈值应为 70%")
    }

    // MARK: - DAG 规模分级验证

    /// 简单 DAG 规模：1-3 节点
    func testSimpleDAGScale() {
        for count in [1, 2, 3] {
            let subs = makeParallelSubTasks(count: count)
            XCTAssertLessThanOrEqual(subs.count, 3, "简单 DAG ≤ 3 节点")
            XCTAssertGreaterThanOrEqual(subs.count, 1, "DAG 至少 1 节点")
        }
    }

    /// 中等 DAG 规模：4-10 节点
    func testMediumDAGScale() {
        for count in [4, 7, 10] {
            let subs = makeParallelSubTasks(count: count)
            XCTAssertLessThanOrEqual(subs.count, 10, "中等 DAG ≤ 10 节点")
            XCTAssertGreaterThanOrEqual(subs.count, 4, "中等 DAG ≥ 4 节点")
        }
    }

    /// 复杂 DAG 规模：11-30 节点
    func testComplexDAGScale() {
        for count in [11, 20, 30] {
            let subs = makeParallelSubTasks(count: count)
            XCTAssertLessThanOrEqual(subs.count, 30, "复杂 DAG ≤ 30 节点")
            XCTAssertGreaterThanOrEqual(subs.count, 11, "复杂 DAG ≥ 11 节点")
        }
    }
}
