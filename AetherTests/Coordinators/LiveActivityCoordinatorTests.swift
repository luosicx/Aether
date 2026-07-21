#if os(iOS)
import XCTest
import ActivityKit
@testable import Aether

/// P2-6 Task 2: LiveActivityCoordinator 单元测试
///
/// 验证 LiveActivityCoordinator 正确封装 Activity<TimerActivityAttributes> 全生命周期：
/// start / update / end。模拟器环境无 ActivityKit 支持，相关测试通过 SIMULATOR_DEVICE_NAME
/// 守卫跳过；testEndWhenNotStartedNoOp 不触及 ActivityKit API，可在模拟器运行。
@MainActor
final class LiveActivityCoordinatorTests: XCTestCase {

    /// 模拟器环境无 ActivityKit 支持，跳过标志
    private var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    }

    /// Live Activities 是否启用（真机用户可能在系统设置中关闭）
    private var activitiesEnabled: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    // MARK: - start

    /// start(query:) 应启动 Live Activity 并设置内部 activity 引用（isStarted == true）
    func testStartLiveActivitySetsActivity() async throws {
        try XCTSkipIf(isSimulator, "跳过：模拟器无 ActivityKit 支持")
        try XCTSkipIf(!activitiesEnabled, "跳过：Live Activities 未启用")

        let coordinator = LiveActivityCoordinator()
        coordinator.start(query: "测试查询")
        // 等待 Activity.request 完成（ActivityKit 异步初始化）
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(coordinator.isStarted, "start 后 isStarted 应为 true")

        // 清理：结束 Activity 避免污染后续测试
        coordinator.end()
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - update

    /// update(status:) 应更新 Live Activity 状态，不改变 isStarted
    func testUpdateLiveActivityChangesStatus() async throws {
        try XCTSkipIf(isSimulator, "跳过：模拟器无 ActivityKit 支持")
        try XCTSkipIf(!activitiesEnabled, "跳过：Live Activities 未启用")

        let coordinator = LiveActivityCoordinator()
        coordinator.start(query: "测试查询")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(coordinator.isStarted, "前置：start 后 isStarted 应为 true")

        coordinator.update(status: "回复中")
        // 等待 update Task 完成
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(coordinator.isStarted, "update 后 isStarted 应保持 true")

        // 清理
        coordinator.end()
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - end

    /// end() 应结束 Live Activity 并清空内部 activity 引用（isStarted == false）
    func testEndLiveActivityClearsActivity() async throws {
        try XCTSkipIf(isSimulator, "跳过：模拟器无 ActivityKit 支持")
        try XCTSkipIf(!activitiesEnabled, "跳过：Live Activities 未启用")

        let coordinator = LiveActivityCoordinator()
        coordinator.start(query: "测试查询")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(coordinator.isStarted, "前置：start 后 isStarted 应为 true")

        coordinator.end()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(coordinator.isStarted, "end 后 isStarted 应为 false")
    }

    // MARK: - 幂等性

    /// 已启动时再次 start 应为 no-op（不崩溃，isStarted 保持 true）
    func testStartWhenAlreadyStartedNoOp() async throws {
        try XCTSkipIf(isSimulator, "跳过：模拟器无 ActivityKit 支持")
        try XCTSkipIf(!activitiesEnabled, "跳过：Live Activities 未启用")

        let coordinator = LiveActivityCoordinator()
        coordinator.start(query: "第一次")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(coordinator.isStarted, "前置：第一次 start 后 isStarted 应为 true")

        // 第二次 start 应为 no-op（不崩溃，不替换现有 activity）
        coordinator.start(query: "第二次")
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(coordinator.isStarted, "第二次 start 后 isStarted 应保持 true")

        // 清理
        coordinator.end()
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    /// 未启动时 end 应为 no-op（不崩溃，isStarted 保持 false）。
    /// 此测试不调用 ActivityKit API（end() 在 activity==nil 时直接 return），可在模拟器运行。
    func testEndWhenNotStartedNoOp() {
        let coordinator = LiveActivityCoordinator()
        // 未启动直接 end，应不崩溃
        coordinator.end()
        XCTAssertFalse(coordinator.isStarted, "未启动时 end 后 isStarted 应为 false")
    }
}
#endif
