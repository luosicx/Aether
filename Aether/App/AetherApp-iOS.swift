#if os(iOS)
import SwiftUI
import SwiftData
import AVFoundation
import BackgroundTasks
import ActivityKit
import AetherServices
import AetherDesign
import AetherUI
import os

/// Task 2.5: iOS 专属 App 入口。配置 BGTaskScheduler、Live Activity、WatchConnectivity。
@main
struct AetherApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // 预热语音引擎：触发 speechsynthesisd daemon 启动和音色库加载
                    Task.detached(priority: .background) {
                        _ = AVSpeechSynthesisVoice.speechVoices()
                    }
                    // 延迟 1 秒让首屏先完成渲染，再发起网络请求
                    try? await Task.sleep(for: .seconds(1))
                    await RemoteConfigService.shared.fetch()
                }
                .preferredColorScheme(.dark)
                .environment(ThemeManager.shared)
        }
        .modelContainer(AetherApp.sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建对话") {
                    NotificationCenter.default.post(name: .newConversationRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("搜索会话") {
                    NotificationCenter.default.post(name: .searchRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("聚焦搜索") {
                    NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    NotificationCenter.default.post(name: .settingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// iOS 初始化：注册 BGTaskScheduler 后台任务 + 共享初始化逻辑
    init() {
        sharedInit()

        // 性能优化：BGTask register 必须在 init 中（系统要求）
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.aether.daily-refresh", using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleDailyRefresh(task: refreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.aether.telemetry-upload", using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleTelemetryUpload(task: refreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.aether.health-insight", using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleHealthInsight(task: refreshTask)
        }
    }

    // MARK: - iOS 后台任务

    /// 调度每日刷新后台任务，最早 24 小时后执行。
    nonisolated static func scheduleDailyRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.aether.daily-refresh")
        request.earliestBeginDate = Date().addingTimeInterval(24 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.app.error("调度每日刷新任务失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func handleDailyRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            Logger.app.warning("每日刷新任务即将过期")
        }
        Logger.app.info("每日刷新后台任务执行中...")
        task.setTaskCompleted(success: true)
        scheduleDailyRefresh()
    }

    /// Day 14: 调度遥测上报后台任务，每 60 分钟触发一次。
    nonisolated static func scheduleTelemetryUpload() {
        let request = BGAppRefreshTaskRequest(identifier: "com.aether.telemetry-upload")
        request.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.app.error("调度遥测上报任务失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func handleTelemetryUpload(task: BGAppRefreshTask) {
        task.expirationHandler = {
            Logger.app.warning("遥测上报任务即将过期")
        }
        Task {
            await LogUploader.shared.uploadIfNeeded()
            task.setTaskCompleted(success: true)
            scheduleTelemetryUpload()
        }
    }

    // MARK: - Day 17: 健康洞察后台任务

    nonisolated static func scheduleHealthInsight() {
        let request = BGAppRefreshTaskRequest(identifier: "com.aether.health-insight")
        let calendar = Calendar.current
        let now = Date()
        var next9AM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        if next9AM <= now {
            next9AM = calendar.date(byAdding: .day, value: 1, to: next9AM) ?? next9AM
        }
        request.earliestBeginDate = next9AM
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.app.error("调度健康洞察任务失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func handleHealthInsight(task: BGAppRefreshTask) {
        task.expirationHandler = {
            Logger.app.warning("健康洞察任务即将过期")
            task.setTaskCompleted(success: false)
        }
        // P1-1/P1-2: HealthInsightGenerator 已标注 @MainActor（ModelContext 非 Sendable，
        // 必须在创建它的 actor 上访问）。BGTask 在后台线程触发，故用 `Task { @MainActor in ... }`
        // 将整个 ModelContext 创建 + 调用链 hop 到主线程，既满足 SwiftData 隔离规则，
        // 又让 ModelContext 生命周期与主线程对齐。
        Task { @MainActor in
            do {
                let container = try ModelContainer(
                    for: Conversation.self, ChatMessage.self, DocumentChunk.self, MessageFeedback.self, HealthInsight.self, UserPreference.self, AgentTask.self, Memory.self,
                    configurations: AetherApp.sharedModelConfiguration
                )
                let context = ModelContext(container)
                let generator = HealthInsightGenerator.make(modelContext: context)
                let insight = try await generator.generateInsight(days: 7)
                generator.sendInsightNotification(insight)
                task.setTaskCompleted(success: true)
            } catch {
                Logger.app.error("健康洞察生成失败: \(error.localizedDescription, privacy: .public)")
                task.setTaskCompleted(success: false)
            }
            scheduleHealthInsight()
        }
    }
}

// MARK: - Day 11: 灵动岛 Live Activity 属性
/// ActivityKit 仅 iOS 16.1+ 可用，调用方需自行用 if #available 包裹
struct TimerActivityAttributes: ActivityAttributes {
    var query: String

    struct ContentState: Codable, Hashable {
        var status: String
        var elapsed: Int
    }
}
#endif
