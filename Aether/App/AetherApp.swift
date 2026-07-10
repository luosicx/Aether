import SwiftUI
import SwiftData
import AVFoundation
#if os(iOS)
import BackgroundTasks
import ActivityKit
#endif

/// Aether App 入口。配置 SwiftData ModelContainer 并注册每日刷新后台任务。
@main
struct AetherApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 500)
                #endif
                .task {
                    // 预热语音引擎：触发 speechsynthesisd daemon 启动和音色库加载，
                    // 避免首次朗读时冷启动阻塞主线程 1-3 秒。仅加载不发声。
                    _ = AVSpeechSynthesisVoice.speechVoices()
                    // 性能优化：远程配置拉取从 init() 移到首屏出现后，避免影响冷启动
                    await RemoteConfigService.shared.fetch()
                }
                // Aether 主题在深色模式下效果最佳，默认启用深色模式
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
        .modelContainer(for: [Conversation.self, ChatMessage.self, DocumentChunk.self, MessageFeedback.self, HealthInsight.self, UserPreference.self])
        // Task 4: macOS 菜单栏 —— 新建对话 / 搜索会话 / 设置
        .commands {
            // File → 新建对话 (Cmd+N)
            CommandGroup(replacing: .newItem) {
                Button("新建对话") {
                    NotificationCenter.default.post(name: .newConversationRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            // Edit → 搜索会话 (Cmd+K)
            CommandGroup(after: .textEditing) {
                Button("搜索会话") {
                    NotificationCenter.default.post(name: .searchRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                // 性能优化：⌘Shift+F 聚焦搜索（直接进入搜索模式并聚焦输入框）
                Button("聚焦搜索") {
                    NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            // App → 设置 (Cmd+,) —— 当前用 sheet 展示设置，手动绑定快捷键
            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    NotificationCenter.default.post(name: .settingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// 初始化 App。注册 BGTaskScheduler 每日刷新后台任务并调度首次执行。
    ///
    /// - Note: App 为 @MainActor 的 struct，init 中 self 为 inout，
    ///   无法被 @escaping 闭包捕获，因此 handler 调用 static 方法（不捕获 self）。
    init() {
        // UITest 数据重置：检测 UITEST_RESET_DATA 启动参数，清空 SwiftData 所有数据
        // 生产环境从不传此参数，行为不受影响
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_DATA") {
            wipeAllDataForUITest()
        }
        #if os(iOS)
        // 性能优化：BGTask register 必须在 init 中（系统要求），schedule 调度延迟到首次进入后台
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
        #endif
        // Day 20: 初始化崩溃监控（Bugly SDK，条件编译保护，未集成时占位）
        let buglyAppKey = Bundle.main.object(forInfoDictionaryKey: "BuglyAppKey") as? String ?? ""
        CrashReportService.shared.initialize(appKey: buglyAppKey)

        // Day 20: 生成匿名用户标识并设置到崩溃监控
        if let existingId = UserDefaults.standard.string(forKey: "anonymous_user_id") {
            CrashReportService.shared.setUserId(existingId)
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "anonymous_user_id")
            CrashReportService.shared.setUserId(newId)
        }
    }

    /// UITest 数据重置：创建独立的 ModelContainer（使用与主 App 相同的默认 store URL），
    /// 调用 ChatStorage.wipeAllData() 清空所有 SwiftData 数据。
    /// 必须在主 App 的 ModelContainer 创建前执行，使后续启动获得干净状态。
    /// 静默失败，不影响 App 启动。
    private func wipeAllDataForUITest() {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try ModelContainer(
                for: Conversation.self, ChatMessage.self, DocumentChunk.self,
                    MessageFeedback.self, HealthInsight.self, UserPreference.self,
                configurations: config
            )
            let context = ModelContext(container)
            ChatStorage(modelContext: context).wipeAllData()
            try context.save()
        } catch {
            // 静默失败，不影响 App 启动
        }
    }

    #if os(iOS)
    /// 调度每日刷新后台任务，最早 24 小时后执行。
    /// nonisolated 允许从后台任务 handler 中调用。
    nonisolated static func scheduleDailyRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.aether.daily-refresh")
        request.earliestBeginDate = Date().addingTimeInterval(24 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("调度每日刷新任务失败: \(error)")
        }
    }

    /// 处理每日刷新后台任务（仅日志，无业务逻辑）。
    /// - Parameter task: BGAppRefreshTask 实例
    /// - Note: 设置 expirationHandler 应对系统回收时间片，完成后重新调度下一次刷新
    nonisolated static func handleDailyRefresh(task: BGAppRefreshTask) {
        // 设置过期处理：系统即将回收任务时间片时触发
        task.expirationHandler = {
            print("每日刷新任务即将过期")
        }
        // 实际逻辑占位
        print("每日刷新后台任务执行中...")
        task.setTaskCompleted(success: true)
        // 重新调度下一次刷新
        scheduleDailyRefresh()
    }

    /// Day 14: 调度遥测上报后台任务，每 60 分钟触发一次。
    /// nonisolated 允许从后台任务 handler 中调用。
    nonisolated static func scheduleTelemetryUpload() {
        let request = BGAppRefreshTaskRequest(identifier: "com.aether.telemetry-upload")
        request.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("调度遥测上报任务失败: \(error)")
        }
    }

    /// Day 14: 处理遥测上报后台任务。调用 LogUploader 上报缓冲事件，完成后重新调度下一次。
    /// - Parameter task: BGAppRefreshTask 实例
    /// - Note: 设置 expirationHandler 应对系统回收时间片，完成后重新调度下一次上报
    nonisolated static func handleTelemetryUpload(task: BGAppRefreshTask) {
        // 设置过期处理：系统即将回收任务时间片时触发
        task.expirationHandler = {
            print("遥测上报任务即将过期")
        }
        // 异步上报缓冲事件，完成后标记任务完成并重新调度下一次
        Task {
            await LogUploader.shared.uploadIfNeeded()
            task.setTaskCompleted(success: true)
            scheduleTelemetryUpload()
        }
    }

    // MARK: - Day 17: 健康洞察后台任务

    /// Day 17: 调度健康洞察生成任务，目标为每天 09:00 触发。
    /// nonisolated 允许从后台任务 handler 中调用。
    nonisolated static func scheduleHealthInsight() {
        let request = BGAppRefreshTaskRequest(identifier: "com.aether.health-insight")
        // 计算下次 09:00 的时间
        let calendar = Calendar.current
        let now = Date()
        var next9AM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        // 若今天 09:00 已过，调度到明天 09:00
        if next9AM <= now {
            next9AM = calendar.date(byAdding: .day, value: 1, to: next9AM) ?? next9AM
        }
        request.earliestBeginDate = next9AM
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("调度健康洞察任务失败: \(error)")
        }
    }

    /// Day 17: 处理健康洞察生成后台任务。
    /// 创建 ModelContext → 调用 HealthInsightGenerator.generateInsight → 推送通知 → 重新调度。
    /// - Parameter task: BGAppRefreshTask 实例
    /// - Note: 设置 expirationHandler 应对系统回收时间片，完成后重新调度下一次生成
    nonisolated static func handleHealthInsight(task: BGAppRefreshTask) {
        // 设置过期处理：系统即将回收任务时间片时触发
        task.expirationHandler = {
            print("健康洞察任务即将过期")
            task.setTaskCompleted(success: false)
        }
        // 异步生成洞察，完成后标记任务完成并重新调度下一次
        Task {
            do {
                // 创建独立的 ModelContainer/Context（后台任务无法访问主 App 的 ModelContext）
                let container = try ModelContainer(
                    for: Conversation.self, ChatMessage.self, DocumentChunk.self, MessageFeedback.self, HealthInsight.self
                )
                let context = ModelContext(container)
                let generator = HealthInsightGenerator.make(modelContext: context)
                let insight = try await generator.generateInsight(days: 7)
                // 推送本地通知
                generator.sendInsightNotification(insight)
                task.setTaskCompleted(success: true)
            } catch {
                print("健康洞察生成失败: \(error)")
                task.setTaskCompleted(success: false)
            }
            // 无论成功失败都重新调度下一次
            scheduleHealthInsight()
        }
    }
    #endif
}

#if os(iOS)
// MARK: - Day 11: 灵动岛 Live Activity 属性
/// ActivityKit 仅 iOS 16.1+ 可用，调用方需自行用 if #available 包裹
struct TimerActivityAttributes: ActivityAttributes {
    /// 用户问题
    var query: String

    /// Live Activity 动态状态
    struct ContentState: Codable, Hashable {
        /// 状态文案：思考中 / 回复中
        var status: String
        /// 已用秒数
        var elapsed: Int
    }
}
#endif

// MARK: - Task 4: macOS 菜单栏命令通知名
// 跨平台定义：macOS 菜单项发出通知，ChatView 监听后触发对应行为；iOS 下不会被触发。
extension Notification.Name {
    /// 菜单「新建对话」(Cmd+N) 触发
    static let newConversationRequested = Notification.Name("newConversationRequested")
    /// 菜单「搜索会话」(Cmd+K) 触发
    static let searchRequested = Notification.Name("searchRequested")
    /// 菜单「聚焦搜索」(Cmd+Shift+F) 触发
    static let focusSearchRequested = Notification.Name("focusSearchRequested")
    /// 菜单「设置」(Cmd+,) 触发
    static let settingsRequested = Notification.Name("settingsRequested")
}

// MARK: - RootView

/// 根视图：在 ChatView 之上叠加品牌 Splash，开屏展示后淡出。
struct RootView: View {
    @State private var showSplash = !ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_SPLASH")
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @State private var hasScheduledBGTasks = false
    #endif

    var body: some View {
        ChatView()
            .overlay {
                if showSplash {
                    BrandSplash(isVisible: $showSplash)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                #if os(iOS)
                // 性能优化：BGTask schedule 延迟到首次进入后台，减少冷启动耗时
                if newPhase == .background && !hasScheduledBGTasks {
                    hasScheduledBGTasks = true
                    AetherApp.scheduleDailyRefresh()
                    AetherApp.scheduleTelemetryUpload()
                    AetherApp.scheduleHealthInsight()
                    WatchConnectivityService.shared.activate()
                }
                #endif
            }
    }
}
