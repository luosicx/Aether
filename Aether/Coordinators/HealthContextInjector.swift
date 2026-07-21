#if os(iOS)
import Foundation
import os
import AetherServices

/// P2-6 Task 5: HealthContextInjector —— 健康上下文注入协调器
///
/// 从 ChatViewModel.handlePreparing 抽取的 Day 17 HealthKit 上下文注入职责：
/// - 通过闭包读取 ChatViewModel 持有的 `healthKitService` / `injectHealthContext` @Observable 属性
/// - 在 ReAct 请求前置阶段构建最近 24h 健康摘要片段（睡眠 / 心率 / 步数），
///   供 handlePreparing 追加到 effectiveSystemPrompt 末尾
///
/// 设计要点：
/// - 整个类型被 `#if os(iOS)` 包裹，macOS 编译为空，无 HealthKit 符号泄漏
/// - 通过闭包回调读取上游状态，不直接持有 @Observable 属性，与 FeedbackCoordinator 同模式
/// - 未授权 / 未启用 / 服务为 nil / fetchDailySummary 抛错时均返回空字符串，便于上层优雅降级
/// - 与原始 ChatViewModel 行为等价（Day 17 实现）
///
/// 并发边界：本类标注 `@MainActor`，闭包在主 actor 上调用；
/// `HealthKitService.fetchDailySummary` 为 async 方法，本类通过 `await` 调用。
@MainActor
final class HealthContextInjector: Coordinator {
    /// HealthKit 服务提供者（读取 ChatViewModel 的 @Observable var healthKitService 当前值）
    /// 返回 nil 表示未注入服务（设置页未开启健康上下文）
    private let healthKitServiceProvider: () -> HealthKitService?
    /// 是否启用健康上下文注入的查询闭包（读取 ChatViewModel 的 @Observable var injectHealthContext 当前值）
    private let injectHealthContextProvider: () -> Bool

    /// 构造器
    /// - Parameters:
    ///   - healthKitServiceProvider: HealthKitService 当前值查询闭包（@MainActor），返回 nil 表示未注入
    ///   - injectHealthContextProvider: injectHealthContext 当前值查询闭包（@MainActor）
    init(healthKitServiceProvider: @escaping () -> HealthKitService?,
         injectHealthContextProvider: @escaping () -> Bool) {
        self.healthKitServiceProvider = healthKitServiceProvider
        self.injectHealthContextProvider = injectHealthContextProvider
    }

    /// 构建健康上下文片段，追加到 systemPrompt 末尾。
    ///
    /// 行为等价于 ChatViewModel 原始 handlePreparing 中的健康注入逻辑：
    /// 1. injectHealthContext == false → 返回空字符串（NoOp）
    /// 2. healthKitService == nil → 返回空字符串
    /// 3. healthKitService.isAuthorized == false → 返回空字符串（fetchDailySummary 内部也会返回全零摘要，
    ///    但此处提前 short-circuit 避免无谓调用）
    /// 4. fetchDailySummary 抛错 → Logger.chat.warning 记录后返回空字符串
    /// 5. 成功 → 返回 "用户最近 24h：睡眠 X.Xh，心率均值 XXbpm，步数 XXXX"
    ///
    /// - Returns: 健康摘要片段字符串；无可用数据时返回空字符串
    func buildHealthContextSnippet() async -> String {
        // 守卫 1：未启用注入开关
        guard injectHealthContextProvider() else { return "" }
        // 守卫 2：未注入 HealthKitService
        guard let healthService = healthKitServiceProvider() else { return "" }
        // 守卫 3：未授权（HealthKitService 内部 fetchDailySummary 会返回全零摘要，此处提前 short-circuit）
        guard healthService.isAuthorized else { return "" }

        // P2-2: do/catch + Logger.warning，便于诊断 HealthKit 失败原因
        let summary: HealthDailySummary?
        do {
            summary = try await healthService.fetchDailySummary()
        } catch {
            Logger.chat.warning("fetchDailySummary 失败：\(error.localizedDescription, privacy: .public)")
            return ""
        }
        guard let summary = summary else { return "" }

        // Day 17 原始格式：用户最近 24h：睡眠 X.Xh，心率均值 XXbpm，步数 XXXX
        let detail = String(format: NSLocalizedString("睡眠 %.1fh，心率均值 %.0fbpm，步数 %d", comment: ""),
                            summary.sleepHours, summary.avgHeartRate, summary.stepCount)
        return String(format: NSLocalizedString("用户最近 24h：%@", comment: ""), detail)
    }
}
#endif
