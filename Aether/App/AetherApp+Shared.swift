import SwiftUI
import SwiftData
import os
import AetherServices
import AetherDesign
import AetherUI

// MARK: - Task 2.5: 共享的 AetherApp 静态属性与方法
// 本文件由 Aether-iOS 和 Aether-macOS 两个 target 共享编译。
// 平台专属入口在 AetherApp-iOS.swift 和 AetherApp-macOS.swift 中。

extension AetherApp {
    /// Task 14: iCloud 同步开关的 UserDefaults 键（控制 CloudKit 启用，默认关闭）。
    static let iCloudSyncEnabledKey = "aether.icloud.enabled"

    /// Task 14: 上次 iCloud 同步时间的 UserDefaults 键。
    /// SwiftData + CloudKit 未公开同步事件回调，此处作为占位记录点供 UI 显示。
    static let lastICloudSyncDateKey = "aether.icloud.lastSyncDate"

    /// Task 14: CloudKit 容器标识（需与 entitlements 中声明一致）。
    static let cloudKitContainerIdentifier = "iCloud.com.aether.app"

    /// Task 14: 是否启用 iCloud 同步（从 UserDefaults 读取，默认关闭）。
    /// ModelContainer 在 App 启动时根据此值决定使用 CloudKit 还是本地存储。
    /// 切换后需重启 App 才能生效（sharedModelContainer 是 static let）。
    static var isICloudSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
    }

    /// Task 14: 写入 iCloud 同步开关。调用方需提示用户重启 App。
    static func setICloudSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: iCloudSyncEnabledKey)
    }

    /// Task 14: 上次 iCloud 同步时间（占位实现：UI 显示用）。
    /// CloudKit 同步事件未公开，当前仅在用户启用同步时记录一次时间戳。
    static var lastICloudSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: lastICloudSyncDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastICloudSyncDateKey) }
    }

    /// Task 4/5: 创建使用 App Group 共享存储的 ModelConfiguration。
    /// 使 iOS / watchOS / Widget 三端读写同一 SQLite store。
    /// App Group 未配置时回退到默认存储（开发/测试兜底）。
    /// Task 14: 受 UserDefaults `aether.icloud.enabled` 控制：
    /// - 开关关闭（默认）：使用 App Group 本地 SQLite 存储
    /// - 开关开启：使用 CloudKit 自动同步（需重启 App 生效）
    static let sharedModelConfiguration: ModelConfiguration = {
        let groupIdentifier = "group.com.aether.app"

        // Task 14.1: 检查 iCloud 同步开关（默认关闭，避免开发环境触发 CloudKit 错误）
        if UserDefaults.standard.bool(forKey: AetherApp.iCloudSyncEnabledKey) {
            // Task 14.3: SwiftData + CloudKit 冲突解决策略说明
            // ---------------------------------------------------------------
            // 默认采用 "last writer wins" (LWW) 策略：
            // - 多设备并发修改同一记录时，以最后一次写入为准
            // - 关键模型（Conversation / ChatMessage）暂不实现复杂合并逻辑
            // - SwiftData 当前未公开 beforeSave 钩子，无法在保存前介入合并
            // - 若需字段级合并（例如累加消息计数），应在 ViewModel 层显式实现
            // - 如启用后出现 CKError 冲突，由 CloudKit 内部自动处理
            //
            // Task 14.1: CloudKit 不支持自定义 URL，使用默认存储位置
            // .automatic 启用 CloudKit 自动同步，container identifier 由 entitlements
            // 中的 com.apple.developer.icloud-container-identifiers 指定（iCloud.com.aether.app）
            return ModelConfiguration(cloudKitDatabase: .automatic)
        }

        // 默认本地存储：App Group 共享（iOS / watchOS / Widget 三端读写同一 SQLite）
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let storeURL = groupURL.appendingPathComponent("Aether.sqlite")
            return ModelConfiguration(url: storeURL)
        }
        return ModelConfiguration(isStoredInMemoryOnly: false)
    }()

    /// 预构建的 ModelContainer，使用 sharedModelConfiguration。
    ///
    /// P1-7: 双重故障兜底策略——
    /// 1. 优先用 sharedModelConfiguration（持久化到 SQLite）
    /// 2. 失败时降级到 in-memory 模式（App 可运行但数据不持久化）
    /// 3. in-memory 也失败时（系统级 SwiftData 故障，几乎不可能发生），
    ///    上报到 CrashReportService 后 fatalError——
    ///    因为 SwiftUI App 启动必须返回 ModelContainer，没有 ModelContainer 时 ChatView
    ///    通过 @Environment(\.modelContext) 访问会立即崩溃，无法显示任何降级 UI。
    ///    此 fatalError 是「无可恢复的最后一道防线」，符合 Swift fatalError 语义。
    static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Conversation.self, ChatMessage.self, DocumentChunk.self,
                    MessageFeedback.self, HealthInsight.self, UserPreference.self, AgentTask.self, Memory.self,
                configurations: AetherApp.sharedModelConfiguration
            )
        } catch {
            // Fallback：内存模式容器，避免 throw 中断 App 启动
            Logger.app.error("持久化 ModelContainer 创建失败，降级到 in-memory 模式: \(error.localizedDescription, privacy: .public)")
            do {
                return try ModelContainer(
                    for: Conversation.self, ChatMessage.self, DocumentChunk.self,
                        MessageFeedback.self, HealthInsight.self, UserPreference.self, AgentTask.self, Memory.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                // 双重故障：持久化 + in-memory 均失败，SwiftData 系统级故障
                // 上报到崩溃监控便于后续定位，然后 fatalError（无法继续）
                CrashReportService.shared.reportException(
                    NSError(domain: "AetherApp", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to create in-memory ModelContainer: \(error)"
                    ])
                )
                fatalError("Failed to create in-memory ModelContainer (SwiftData 系统级故障): \(error)")
            }
        }
    }()

    /// UITest 数据重置：创建独立的 ModelContainer（使用与主 App 相同的默认 store URL），
    /// 调用 ChatStorage.wipeAllData() 清空所有 SwiftData 数据。
    func wipeAllDataForUITest() {
        do {
            let container = try ModelContainer(
                for: Conversation.self, ChatMessage.self, DocumentChunk.self,
                    MessageFeedback.self, HealthInsight.self, UserPreference.self, AgentTask.self, Memory.self,
                configurations: AetherApp.sharedModelConfiguration
            )
            let context = ModelContext(container)
            ChatStorage(modelContext: context).wipeAllData()
            try context.save()
        } catch {
            // 静默失败，不影响 App 启动
        }
    }

    /// 跨平台初始化逻辑：崩溃监控 + 匿名用户标识 + BFF Token 迁移
    func sharedInit() {
        // Task 7.6: 日志级别过滤说明
        // os.Logger 的日志级别过滤由系统在 OSLog 层自动处理，无需代码层全局过滤：
        // - .debug：仅在 Console.app/log stream 实时连接时采集，Release 构建不持久化到磁盘
        // - .info：持久化但可能被系统按存储压力回收
        // - .notice/.error/.fault：始终持久化并计入性能指标
        // 因此 Release 构建中 .debug 日志自动过滤，开发期可用 Console.app 查看全部级别。

        // UITest 数据重置
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_DATA") {
            wipeAllDataForUITest()
        }

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

        // Task 5: 启动时迁移可能遗留的 BFF Token 到 Keychain
        SettingsViewModel.migrateLegacyBFFConfigIfNeeded()
    }
}

// MARK: - Task 4: 菜单栏命令通知名（跨平台定义）
extension Notification.Name {
    /// 菜单「新建对话」(Cmd+N) 触发
    static let newConversationRequested = Notification.Name("newConversationRequested")
    /// 菜单「搜索会话」(Cmd+K) 触发
    static let searchRequested = Notification.Name("searchRequested")
    /// 菜单「聚焦搜索」(Cmd+Shift+F) 触发
    static let focusSearchRequested = Notification.Name("focusSearchRequested")
    /// 菜单「设置」(Cmd+,) 触发
    static let settingsRequested = Notification.Name("settingsRequested")
    /// 菜单「新建窗口」(Cmd+Shift+N) 触发——仅 macOS
    static let newWindowRequested = Notification.Name("newWindowRequested")
    /// 菜单栏面板点击最近对话时触发
    static let openConversationFromMenuBar = Notification.Name("openConversationFromMenuBar")
    /// 设置页关闭后触发——通知聊天界面重新加载用户偏好
    static let settingsDidUpdate = Notification.Name("settingsDidUpdate")
}

// MARK: - RootView（跨平台根视图）

/// 根视图：在 ChatView 之上叠加品牌 Splash，开屏展示后淡出。
struct RootView: View {
    @State private var showSplash = !ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_SPLASH")
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ChatView()
            .overlay {
                if showSplash {
                    BrandSplash(isVisible: $showSplash)
                }
            }
            .task {
                // Task: 修复主题双数据源——App 启动时从 UserPreference 同步到 ThemeManager
                let pref = ChatStorage(modelContext: modelContext).fetchPreference()
                ThemeManager.shared.switchTheme(byName: pref.themeName)
            }
            .onChange(of: scenePhase) { _, newPhase in
                #if os(iOS)
                // 性能优化：BGTask schedule 延迟到首次进入后台
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

    #if os(iOS)
    @State private var hasScheduledBGTasks = false
    #endif
}
