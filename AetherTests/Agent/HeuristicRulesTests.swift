import XCTest
import AetherFoundation
import AetherServices
@testable import Aether

/// Task 20 阶段 1: HeuristicRules 单元测试
///
/// 覆盖：
/// - 默认参数（深度 3 / 宽度 8 / 总数 50）
/// - 深度/宽度/总数约束判断
/// - 宽度截断
/// - 复杂度启发式（描述长度 > 100 字、连接词触发）
/// - 同层兄弟 DAG 依赖生成（串行/parallel 混合）
/// - Kahn 拓扑排序
/// - 循环依赖检测
/// - DAG 合法性校验（缺失依赖 / 循环依赖 / 自环）
@MainActor
final class HeuristicRulesTests: XCTestCase {

    // MARK: - 默认参数

    func testDefaultParameters() {
        let rules = HeuristicRules.default
        XCTAssertEqual(rules.maxDepth, 3)
        XCTAssertEqual(rules.maxWidth, 8)
        XCTAssertEqual(rules.maxTotalCount, 50)
        XCTAssertEqual(rules.complexityLengthThreshold, 100)
        XCTAssertFalse(rules.complexityConnectors.isEmpty)
        XCTAssertTrue(rules.complexityConnectors.contains("并且"))
        XCTAssertTrue(rules.complexityConnectors.contains("然后"))
    }

    func testCustomParameters() {
        let rules = HeuristicRules(maxDepth: 2, maxWidth: 5, maxTotalCount: 20, complexityLengthThreshold: 50, complexityConnectors: ["并且"])
        XCTAssertEqual(rules.maxDepth, 2)
        XCTAssertEqual(rules.maxWidth, 5)
        XCTAssertEqual(rules.maxTotalCount, 20)
        XCTAssertEqual(rules.complexityLengthThreshold, 50)
        XCTAssertEqual(rules.complexityConnectors, ["并且"])
    }

    // MARK: - 深度/宽度/总数约束

    func testCanDecomposeDepth() {
        let rules = HeuristicRules.default
        XCTAssertTrue(rules.canDecompose(depth: 0), "depth 0 应可分解")
        XCTAssertTrue(rules.canDecompose(depth: 1), "depth 1 应可分解")
        XCTAssertTrue(rules.canDecompose(depth: 2), "depth 2 应可分解")
        XCTAssertFalse(rules.canDecompose(depth: 3), "depth 3 不应可分解（已达 maxDepth）")
        XCTAssertFalse(rules.canDecompose(depth: 4), "depth 4 不应可分解")
    }

    func testIsWidthValid() {
        let rules = HeuristicRules.default
        XCTAssertTrue(rules.isWidthValid(0))
        XCTAssertTrue(rules.isWidthValid(8))
        XCTAssertFalse(rules.isWidthValid(9))
        XCTAssertFalse(rules.isWidthValid(100))
    }

    func testIsTotalCountValid() {
        let rules = HeuristicRules.default
        XCTAssertTrue(rules.isTotalCountValid(0))
        XCTAssertTrue(rules.isTotalCountValid(50))
        XCTAssertFalse(rules.isTotalCountValid(51))
        XCTAssertFalse(rules.isTotalCountValid(100))
    }

    // MARK: - 宽度截断

    func testClampWidthNoTruncation() {
        let rules = HeuristicRules.default
        let subTasks = (0..<5).map { i in SubTask(title: "T\(i)", order: i) }
        let result = rules.clampWidth(subTasks)
        XCTAssertEqual(result.count, 5)
    }

    func testClampWidthTruncatesTo8() {
        let rules = HeuristicRules.default
        let subTasks = (0..<12).map { i in SubTask(title: "T\(i)", order: i) }
        let result = rules.clampWidth(subTasks)
        XCTAssertEqual(result.count, 8, "应截断到 maxWidth=8")
        XCTAssertEqual(result.first?.title, "T0")
        XCTAssertEqual(result.last?.title, "T7")
    }

    // MARK: - 复杂度启发式

    func testShouldDecomposeFurtherEmptyDescription() {
        let rules = HeuristicRules.default
        XCTAssertFalse(rules.shouldDecomposeFurther(description: ""))
    }

    func testShouldDecomposeFurtherShortDescription() {
        let rules = HeuristicRules.default
        XCTAssertFalse(rules.shouldDecomposeFurther(description: "简单任务"))
    }

    func testShouldDecomposeFurtherLongDescription() {
        let rules = HeuristicRules.default
        let longDesc = String(repeating: "a", count: 101)
        XCTAssertTrue(rules.shouldDecomposeFurther(description: longDesc))
    }

    func testShouldDecomposeFurtherExactlyAtThreshold() {
        let rules = HeuristicRules.default
        let desc = String(repeating: "a", count: 100)
        XCTAssertFalse(rules.shouldDecomposeFurther(description: desc), "恰好 100 字符不应触发")
    }

    func testShouldDecomposeFurtherConnector并且() {
        let rules = HeuristicRules.default
        XCTAssertTrue(rules.shouldDecomposeFurther(description: "做A，并且做B"))
    }

    func testShouldDecomposeFurtherConnector然后() {
        let rules = HeuristicRules.default
        XCTAssertTrue(rules.shouldDecomposeFurther(description: "先做A然后做B"))
    }

    func testShouldDecomposeFurtherNoConnector() {
        let rules = HeuristicRules.default
        XCTAssertFalse(rules.shouldDecomposeFurther(description: "做A做B做C"))
    }

    func testShouldDecomposeSubTaskAtDepthExceeded() {
        let rules = HeuristicRules.default
        let sub = SubTask(title: "复杂任务", description: String(repeating: "a", count: 200))
        // depth=3 时不应再分解（maxDepth=3）
        XCTAssertFalse(rules.shouldDecompose(subTask: sub, atDepth: 3, currentTotalCount: 1))
    }

    func testShouldDecomposeSubTaskAtTotalCountExceeded() {
        let rules = HeuristicRules.default
        let sub = SubTask(title: "复杂任务", description: String(repeating: "a", count: 200))
        XCTAssertFalse(rules.shouldDecompose(subTask: sub, atDepth: 1, currentTotalCount: 50))
    }

    func testShouldDecomposeSubTaskNormal() {
        let rules = HeuristicRules.default
        let sub = SubTask(title: "复杂任务", description: "做A然后做B并且做C")
        XCTAssertTrue(rules.shouldDecompose(subTask: sub, atDepth: 1, currentTotalCount: 1))
    }

    // MARK: - 同层兄弟 DAG 依赖生成

    func testGenerateSiblingDependenciesEmpty() {
        let rules = HeuristicRules.default
        XCTAssertTrue(rules.generateSiblingDependencies([]).isEmpty)
    }

    func testGenerateSiblingDependenciesSingle() {
        let rules = HeuristicRules.default
        let sub = SubTask(title: "T", dependencies: [UUID(), UUID()], order: 0)
        let result = rules.generateSiblingDependencies([sub])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].dependencies.isEmpty, "单节点应清空依赖")
    }

    func testGenerateSiblingDependenciesSerial() {
        let rules = HeuristicRules.default
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", order: 1)
        let s3 = SubTask(title: "T3", order: 2)
        let result = rules.generateSiblingDependencies([s1, s2, s3])
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].dependencies.isEmpty, "第一个节点应无依赖")
        XCTAssertEqual(result[1].dependencies, [result[0].id], "第二个节点应依赖第一个")
        XCTAssertEqual(result[2].dependencies, [result[1].id], "第三个节点应依赖第二个")
    }

    func testGenerateSiblingDependenciesAllParallel() {
        let rules = HeuristicRules.default
        let s1 = SubTask(title: "T1", order: 0, parallel: true)
        let s2 = SubTask(title: "T2", order: 1, parallel: true)
        let s3 = SubTask(title: "T3", order: 2, parallel: true)
        let result = rules.generateSiblingDependencies([s1, s2, s3])
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.dependencies.isEmpty }, "全部 parallel 节点应无依赖")
    }

    func testGenerateSiblingDependenciesMixedParallelSerial() {
        let rules = HeuristicRules.default
        // s1 parallel, s2 serial, s3 parallel, s4 serial
        let s1 = SubTask(title: "T1", order: 0, parallel: true)
        let s2 = SubTask(title: "T2", order: 1, parallel: false)
        let s3 = SubTask(title: "T3", order: 2, parallel: true)
        let s4 = SubTask(title: "T4", order: 3, parallel: false)
        let result = rules.generateSiblingDependencies([s1, s2, s3, s4])
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result[0].dependencies.isEmpty, "第一个节点应无依赖")
        XCTAssertTrue(result[1].dependencies.isEmpty, "s2 前面全是 parallel，应无依赖")
        XCTAssertTrue(result[2].dependencies.isEmpty, "s3 parallel 应无依赖")
        XCTAssertEqual(result[3].dependencies, [result[1].id], "s4 应依赖 s2（最近一个非 parallel）")
    }

    // MARK: - 拓扑排序与循环检测

    func testTopologicalSortSimpleChain() {
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", dependencies: [s1.id], order: 1)
        let s3 = SubTask(title: "T3", dependencies: [s2.id], order: 2)
        let (isAcyclic, order) = HeuristicRules.topologicalSort([s1, s2, s3])
        XCTAssertTrue(isAcyclic)
        XCTAssertEqual(order, [s1.id, s2.id, s3.id])
    }

    func testTopologicalSortParallel() {
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", order: 1)
        let s3 = SubTask(title: "T3", dependencies: [s1.id, s2.id], order: 2)
        let (isAcyclic, order) = HeuristicRules.topologicalSort([s1, s2, s3])
        XCTAssertTrue(isAcyclic)
        XCTAssertEqual(order.count, 3)
        // s3 应在最后
        XCTAssertEqual(order.last, s3.id)
        // s1, s2 应在 s3 之前（顺序可能任意）
        XCTAssertTrue(order.contains(s1.id))
        XCTAssertTrue(order.contains(s2.id))
    }

    func testHasCycleNoCycle() {
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", dependencies: [s1.id], order: 1)
        XCTAssertFalse(HeuristicRules.hasCycle([s1, s2]))
    }

    func testHasCycleWithCycle() {
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", dependencies: [s1.id], order: 1)
        let s3 = SubTask(title: "T3", dependencies: [s2.id], order: 2)
        var s1WithDep = s1
        s1WithDep.dependencies = [s3.id] // 形成环：s1 -> s3 -> s2 -> s1
        XCTAssertTrue(HeuristicRules.hasCycle([s1WithDep, s2, s3]))
    }

    func testHasCycleSelfLoop() {
        let s1 = SubTask(title: "T1", order: 0)
        var s1WithSelf = s1
        s1WithSelf.dependencies = [s1.id]
        XCTAssertTrue(HeuristicRules.hasCycle([s1WithSelf]), "自环应视为循环依赖")
    }

    // MARK: - DAG 合法性校验

    func testValidateDAGValid() {
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", dependencies: [s1.id], order: 1)
        let (isValid, reason) = HeuristicRules.validateDAG([s1, s2])
        XCTAssertTrue(isValid)
        XCTAssertNil(reason)
    }

    func testValidateDAGMissingDependency() {
        let s1 = SubTask(title: "T1", order: 0)
        let missingID = UUID()
        let s2 = SubTask(title: "T2", dependencies: [missingID], order: 1)
        let (isValid, reason) = HeuristicRules.validateDAG([s1, s2])
        XCTAssertFalse(isValid, "缺失依赖应校验失败")
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("不存在") ?? false, "原因应说明依赖不存在")
    }

    func testValidateDAGWithCycle() {
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", dependencies: [s1.id], order: 1)
        var s1WithDep = s1
        s1WithDep.dependencies = [s2.id]
        let (isValid, reason) = HeuristicRules.validateDAG([s1WithDep, s2])
        XCTAssertFalse(isValid)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("循环") ?? false, "原因应说明存在循环依赖")
    }

    // MARK: - 验收标准对齐

    /// 验收 1: 深度 ≤ 3、宽度 ≤ 8、总数 ≤ 50、无循环依赖
    func testAcceptanceCriteriaHeuristicBounds() {
        let rules = HeuristicRules.default
        XCTAssertLessThanOrEqual(rules.maxDepth, 3)
        XCTAssertLessThanOrEqual(rules.maxWidth, 8)
        XCTAssertLessThanOrEqual(rules.maxTotalCount, 50)
    }
}
