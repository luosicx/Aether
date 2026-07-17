import XCTest
import SwiftUI
@testable import Aether

/// Task 20 阶段 4: DAGVisualizationView 单元测试
///
/// 覆盖：
/// - collapseThreshold 常量
/// - NodeLayout 结构体属性与 Identifiable 契约
/// - EdgeLayout 结构体属性与 Hashable 契约
/// - AgentTask.progressRatio / completedCount / hasFailedSubTask（View 依赖）
/// - DAGVisualizationView 可被初始化
///
/// 注：Canvas 绘制与 private 颜色映射逻辑无法在单元测试中直接验证，
/// 通过依赖模型与初始化契约保证 View 正确性。
@MainActor
final class DAGVisualizationViewTests: XCTestCase {

    // MARK: - 常量

    /// collapseThreshold 应为 30
    func testCollapseThresholdConstant() {
        XCTAssertEqual(DAGVisualizationView.collapseThreshold, 30, "折叠阈值应为 30")
    }

    // MARK: - NodeLayout

    /// NodeLayout 拥有稳定 id（Identifiable 契约）
    func testNodeLayoutIsIdentifiable() {
        let id = UUID()
        let sub = SubTask(title: "测试")
        let frame = CGRect(x: 0, y: 0, width: 100, height: 36)
        let layout = DAGVisualizationView.NodeLayout(id: id, subTask: sub, frame: frame, depth: 0)

        XCTAssertEqual(layout.id, id, "id 应为传入值")
        let _: UUID = layout.id  // 编译期验证 Identifiable 类型
    }

    /// NodeLayout 正确存储 subTask / frame / depth
    func testNodeLayoutStoresFields() {
        let id = UUID()
        let sub = SubTask(title: "节点A", description: "描述", order: 1)
        let frame = CGRect(x: 10, y: 20, width: 100, height: 36)
        let layout = DAGVisualizationView.NodeLayout(id: id, subTask: sub, frame: frame, depth: 2)

        XCTAssertEqual(layout.subTask.title, "节点A")
        XCTAssertEqual(layout.subTask.description, "描述")
        XCTAssertEqual(layout.frame, frame)
        XCTAssertEqual(layout.depth, 2)
    }

    /// 两个 NodeLayout 的 id 不同即视为不同（用于 ForEach 唯一性）
    func testNodeLayoutUniqueIds() {
        let sub = SubTask(title: "节点")
        let frame = CGRect(x: 0, y: 0, width: 100, height: 36)
        let layout1 = DAGVisualizationView.NodeLayout(id: UUID(), subTask: sub, frame: frame, depth: 0)
        let layout2 = DAGVisualizationView.NodeLayout(id: UUID(), subTask: sub, frame: frame, depth: 0)

        XCTAssertNotEqual(layout1.id, layout2.id, "不同实例 id 应不同")
    }

    // MARK: - EdgeLayout

    /// EdgeLayout 正确存储 from / to
    func testEdgeLayoutStoresFields() {
        let from = UUID()
        let to = UUID()
        let edge = DAGVisualizationView.EdgeLayout(from: from, to: to)

        XCTAssertEqual(edge.from, from)
        XCTAssertEqual(edge.to, to)
    }

    /// EdgeLayout Hashable：可放入 Set / Dictionary
    func testEdgeLayoutHashable() {
        let from = UUID()
        let to = UUID()
        let edge1 = DAGVisualizationView.EdgeLayout(from: from, to: to)
        let edge2 = DAGVisualizationView.EdgeLayout(from: from, to: to)
        let edge3 = DAGVisualizationView.EdgeLayout(from: to, to: from)

        let set: Set<DAGVisualizationView.EdgeLayout> = [edge1, edge2, edge3]
        XCTAssertEqual(set.count, 2, "edge1 与 edge2 相同应去重，edge3 不同应保留")
    }

    /// EdgeLayout Equatable：相同 from/to 视为相等
    func testEdgeLayoutEquality() {
        let from = UUID()
        let to = UUID()
        let edge1 = DAGVisualizationView.EdgeLayout(from: from, to: to)
        let edge2 = DAGVisualizationView.EdgeLayout(from: from, to: to)

        XCTAssertEqual(edge1, edge2)
    }

    // MARK: - AgentTask 依赖属性（View 渲染依赖）

    /// progressRatio：全部 completed 时为 1.0
    func testProgressRatioAllCompleted() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        task.updateSubTasks([s1, s2])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        _ = task.updateSubTaskStatus(id: s2.id, status: .completed)

        XCTAssertEqual(task.progressRatio, 1.0, "全部完成时 progressRatio 应为 1.0")
    }

    /// progressRatio：空子任务时为 0
    func testProgressRatioEmptySubTasks() {
        let task = AgentTask(goal: "测试")
        XCTAssertEqual(task.progressRatio, 0, "空子任务 progressRatio 应为 0")
    }

    /// progressRatio：含 skipped 节点
    func testProgressRatioWithSkipped() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        task.updateSubTasks([s1, s2])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        _ = task.updateSubTaskStatus(id: s2.id, status: .skipped)

        XCTAssertEqual(task.progressRatio, 1.0, "skipped 计入已完成比例")
    }

    /// progressRatio：部分完成
    func testProgressRatioPartial() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        let s3 = SubTask(title: "三", order: 2)
        let s4 = SubTask(title: "四", order: 3)
        task.updateSubTasks([s1, s2, s3, s4])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        _ = task.updateSubTaskStatus(id: s2.id, status: .completed)

        XCTAssertEqual(task.progressRatio, 0.5, accuracy: 0.001, "4 个中 2 个完成应 0.5")
    }

    /// hasFailedSubTask：存在 failed 时为 true
    func testHasFailedSubTaskTrue() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        task.updateSubTasks([s1, s2])
        _ = task.updateSubTaskStatus(id: s2.id, status: .failed)

        XCTAssertTrue(task.hasFailedSubTask, "存在 failed 节点应为 true")
    }

    /// hasFailedSubTask：无 failed 时为 false
    func testHasFailedSubTaskFalse() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "一", order: 0)
        task.updateSubTasks([s1])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)

        XCTAssertFalse(task.hasFailedSubTask)
    }

    /// completedCount：completed + skipped 都计入
    func testCompletedCountIncludesSkipped() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        let s3 = SubTask(title: "三", order: 2)
        task.updateSubTasks([s1, s2, s3])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        _ = task.updateSubTaskStatus(id: s2.id, status: .skipped)

        XCTAssertEqual(task.completedCount, 2, "completed + skipped 都应计入")
    }

    // MARK: - DAGVisualizationView 初始化

    /// DAGVisualizationView 可被创建（不崩溃）
    func testViewInitWithEmptyTask() {
        let task = AgentTask(goal: "空任务")
        _ = DAGVisualizationView(task: task)
    }

    /// DAGVisualizationView 可被创建（带子任务）
    func testViewInitWithSubTasks() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "步骤一", order: 0)
        let s2 = SubTask(title: "步骤二", dependencies: [s1.id], order: 1)
        task.updateSubTasks([s1, s2])
        _ = DAGVisualizationView(task: task)
    }

    /// DAGVisualizationView 支持 onNodeTap 回调
    func testViewInitWithNodeTapCallback() {
        let task = AgentTask(goal: "测试")
        var tappedNode: SubTask?
        let view = DAGVisualizationView(task: task, onNodeTap: { sub in
            tappedNode = sub
        })
        // 触发回调
        let testNode = SubTask(title: "测试")
        view.onNodeTap?(testNode)
        XCTAssertEqual(tappedNode?.title, "测试")
    }

    // MARK: - 折叠行为（通过 AgentTask.subTasks.count 与阈值对照）

    /// 节点数超过阈值时触发折叠逻辑（验证阈值常量与节点数关系）
    func testCollapseBehaviorWhenExceedingThreshold() {
        let task = AgentTask(goal: "测试")
        let subs = (0..<35).map { SubTask(title: "节点\($0)", order: $0) }
        task.updateSubTasks(subs)

        XCTAssertGreaterThan(task.subTasks.count, DAGVisualizationView.collapseThreshold,
                             "35 节点应超过阈值 30")
    }

    /// 节点数未超过阈值时无需折叠
    func testNoCollapseWhenBelowThreshold() {
        let task = AgentTask(goal: "测试")
        let subs = (0..<10).map { SubTask(title: "节点\($0)", order: $0) }
        task.updateSubTasks(subs)

        XCTAssertLessThanOrEqual(task.subTasks.count, DAGVisualizationView.collapseThreshold,
                                  "10 节点未超过阈值 30")
    }
}
