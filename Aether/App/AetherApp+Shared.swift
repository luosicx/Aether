import SwiftUI
import SwiftData
import AetherServices
import AetherDesign
import AetherUI

// MARK: - Task 2.5: 共享的 AetherApp 静态属性与方法
// 本文件由 Aether-iOS 和 Aether-macOS 两个 target 共享编译。
// 平台专属入口在 AetherApp-iOS.swift 和 AetherApp-macOS.swift 中。

extension AetherApp {
    /// Task 4/5: 创建使用 App Group 共享存储的 ModelConfiguration。
    /// 使 iOS / watchOS / Widget 三端读写同一 SQLite store。
    /// App Group 未配置时回退到默认存储（开发/测试兜底）。
    static let sharedModelConfiguration: ModelConfiguration = {
        let groupIdentifier = "group.com.aether.app"
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let storeURL = groupURL.appendingPathComponent("Aether.sqlite")
            return ModelConfiguration(url: storeURL)
        }
        return ModelConfiguration(isStoredInMemoryOnly: false)
    }()

    /// 预构建的 ModelContainer，使用 sharedModelConfiguration。
    static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Conversation.self, ChatMessage.self, DocumentChunk.self,
                    MessageFeedback.self, HealthInsight.self, UserPreference.self, AgentTask.self, Memory.self,
                configurations: AetherApp.sharedModelConfiguration
            )
        } catch {
            return try! ModelContainer(
                for: Conversation.self, ChatMessage.self, DocumentChunk.self,
                    MessageFeedback.self, HealthInsight.self, UserPreference.self, AgentTask.self, Memory.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
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
