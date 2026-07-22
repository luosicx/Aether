#if os(iOS)
import Foundation
import ActivityKit

/// P2-6 Task 2: LiveActivityCoordinator —— iOS 灵动岛协调器
///
/// 从 ChatViewModel 抽取的 `Activity<TimerActivityAttributes>` 全生命周期管理职责。
/// 封装 start / update / end 三个操作，内部持有 activity 引用，对外仅暴露 String 参数。
/// 整个类型被 `#if os(iOS)` 包裹，macOS 不编译此文件，无 ActivityKit 符号泄漏。
///
/// 并发边界：本类标注 `@MainActor`，所有操作在主 actor 上调用；
/// `update` / `end` 内部派发 Task 调用 ActivityKit async API（与 ChatViewModel 原实现一致）。
@MainActor
final class LiveActivityCoordinator: Coordinator {
    /// 内部持有的 Live Activity 引用，nil 表示未启动
    private var activity: Activity<TimerActivityAttributes>?

    /// 是否已启动 Live Activity（内部状态查询，便于测试与外部判断）
    internal var isStarted: Bool { activity != nil }

    /// 构造器（无依赖，状态由各方法显式管理）
    init() {} // 无需初始化逻辑：activity 属性默认 nil，由 start(query:) 按需创建

    /// 启动灵动岛（iOS 16.1+ 可用，低版本静默降级）。
    /// 已启动时再次调用为 no-op，不替换现有 activity。
    /// - Parameter query: 用户查询文本，显示在灵动岛上
    func start(query: String) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // 已启动则 no-op
        if activity != nil { return }
        let attributes = TimerActivityAttributes(query: query)
        let state = TimerActivityAttributes.ContentState(status: "思考中", elapsed: 0)
        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        } catch {
            // 启动失败静默，不影响主流程
        }
    }

    /// 更新灵动岛状态。未启动时为 no-op。
    /// - Parameter status: 新状态文本
    func update(status: String) {
        guard #available(iOS 16.1, *), let activity = activity else { return }
        let state = TimerActivityAttributes.ContentState(status: status, elapsed: 0)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// 结束灵动岛。未启动时为 no-op。
    func end() {
        guard #available(iOS 16.1, *), let activity = activity else { return }
        let state = TimerActivityAttributes.ContentState(status: "完成", elapsed: 0)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
#endif
