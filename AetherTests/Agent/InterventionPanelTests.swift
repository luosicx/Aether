import XCTest
import SwiftUI
@testable import Aether

/// Task 20 阶段 4: InterventionPanel 单元测试
///
/// 覆盖：
/// - Action 枚举 rawValue
/// - Action CaseIterable
/// - InterventionPanel 可被初始化
/// - failedNode 正确存储
/// - 回调闭包可被触发
///
/// 注：UI 渲染与 @State 串行化逻辑无法在单元测试中直接验证，
/// 通过 Action 枚举契约与初始化保证 View 正确性。
@MainActor
final class InterventionPanelTests: XCTestCase {

    // MARK: - Action 枚举

    /// Action rawValue 正确
    func testActionRawValues() {
        XCTAssertEqual(InterventionPanel.Action.skip.rawValue, "跳过")
        XCTAssertEqual(InterventionPanel.Action.retry.rawValue, "重试")
        XCTAssertEqual(InterventionPanel.Action.cancel.rawValue, "取消")
    }

    /// Action CaseIterable：按声明顺序返回所有 case
    func testActionCaseIterable() {
        let allCases = InterventionPanel.Action.allCases
        XCTAssertEqual(allCases.count, 3, "应有 3 个 case")
        XCTAssertEqual(allCases, [.skip, .retry, .cancel])
    }

    /// Action Equatable：相同 case 相等
    func testActionEquality() {
        XCTAssertEqual(InterventionPanel.Action.skip, .skip)
        XCTAssertNotEqual(InterventionPanel.Action.skip, .retry)
        XCTAssertNotEqual(InterventionPanel.Action.retry, .cancel)
    }

    /// Action Hashable：可放入 Set
    func testActionHashable() {
        let set: Set<InterventionPanel.Action> = [.skip, .retry, .cancel, .skip, .retry]
        XCTAssertEqual(set.count, 3, "重复 case 应去重")
    }

    // MARK: - InterventionPanel 初始化

    /// InterventionPanel 可被创建（不崩溃）
    func testViewInitWithFailedNode() {
        let node = SubTask(title: "失败节点", order: 0)
        _ = InterventionPanel(
            failedNode: node,
            onSkip: {},
            onRetry: {},
            onCancel: {}
        )
    }

    /// InterventionPanel 正确存储 failedNode
    func testViewStoresFailedNode() {
        var node = SubTask(title: "API 调用失败", description: "获取天气", order: 2)
        node.status = .failed
        node.result = "超时"

        let view = InterventionPanel(
            failedNode: node,
            onSkip: {},
            onRetry: {},
            onCancel: {}
        )

        XCTAssertEqual(view.failedNode.title, "API 调用失败")
        XCTAssertEqual(view.failedNode.status, .failed)
        XCTAssertEqual(view.failedNode.result, "超时")
    }

    // MARK: - 回调触发

    /// onSkip 回调可被触发
    func testOnSkipCallbackInvoked() async {
        let node = SubTask(title: "失败节点", order: 0)
        let exp = expectation(description: "onSkip called")

        let view = InterventionPanel(
            failedNode: node,
            onSkip: { exp.fulfill() },
            onRetry: {},
            onCancel: {}
        )
        await view.onSkip()
        wait(for: [exp], timeout: 1.0)
    }

    /// onRetry 回调可被触发
    func testOnRetryCallbackInvoked() async {
        let node = SubTask(title: "失败节点", order: 0)
        let exp = expectation(description: "onRetry called")

        let view = InterventionPanel(
            failedNode: node,
            onSkip: {},
            onRetry: { exp.fulfill() },
            onCancel: {}
        )
        await view.onRetry()
        wait(for: [exp], timeout: 1.0)
    }

    /// onCancel 回调可被触发
    func testOnCancelCallbackInvoked() async {
        let node = SubTask(title: "失败节点", order: 0)
        let exp = expectation(description: "onCancel called")

        let view = InterventionPanel(
            failedNode: node,
            onSkip: {},
            onRetry: {},
            onCancel: { exp.fulfill() }
        )
        await view.onCancel()
        wait(for: [exp], timeout: 1.0)
    }

    /// 所有回调互不干扰
    func testCallbacksIndependent() async {
        let node = SubTask(title: "失败节点", order: 0)
        var skipCount = 0
        var retryCount = 0
        var cancelCount = 0

        let view = InterventionPanel(
            failedNode: node,
            onSkip: { skipCount += 1 },
            onRetry: { retryCount += 1 },
            onCancel: { cancelCount += 1 }
        )
        await view.onSkip()
        await view.onRetry()
        await view.onRetry()
        await view.onCancel()

        XCTAssertEqual(skipCount, 1)
        XCTAssertEqual(retryCount, 2)
        XCTAssertEqual(cancelCount, 1)
    }

    // MARK: - SubTask 状态映射（View 渲染依赖）

    /// failed 节点状态正确（用于 InterventionPanel 触发条件）
    func testFailedNodeStatusMapping() {
        let task = AgentTask(goal: "测试")
        let s1 = SubTask(title: "成功", order: 0)
        let s2 = SubTask(title: "失败", order: 1)
        task.updateSubTasks([s1, s2])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        _ = task.updateSubTaskStatus(id: s2.id, status: .failed, result: "网络错误")

        XCTAssertTrue(task.hasFailedSubTask)
        let failed = task.subTasks.first { $0.status == .failed }
        XCTAssertNotNil(failed)
        XCTAssertEqual(failed?.title, "失败")
        XCTAssertEqual(failed?.result, "网络错误")
    }

    /// 五种 SubTaskStatus 都可被 InterventionPanel 处理（不崩溃）
    func testInterventionPanelHandlesAllStatuses() {
        for status in [SubTaskStatus.pending, .inProgress, .completed, .failed, .skipped] {
            var node = SubTask(title: "节点", order: 0)
            node.status = status
            _ = InterventionPanel(
                failedNode: node,
                onSkip: {},
                onRetry: {},
                onCancel: {}
            )
        }
    }
}
