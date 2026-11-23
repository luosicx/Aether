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

    /// 本进程实际生效的存储后端，供 UI 提示与诊断使用。
    enum StoreBackend: Equatable {
        /// SwiftData + CloudKit 同步生效
        case cloudKit
        /// 本地持久化（App Group SQLite，不同步）
        case local
        /// 兜底内存存储（数据不持久化）
        case inMemory
    }

    private static func makeModelContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Conversation.self, ChatMessage.self, DocumentChunk.self,
                MessageFeedback.self, HealthInsight.self, UserPreference.self, AgentTask.self, Memory.self,
            configurations: configuration
        )
    }

    /// 本地存储配置：App Group 共享 SQLite（iOS / watchOS / Widget 三端读写同一 store）。
    ///
    /// 必须显式 cloudKitDatabase: .none——ModelConfiguration 默认是 .automatic，
    /// 一旦二进制带 iCloud entitlement（签名/真机构建），SwiftData 会自动为本地 store
    /// 启用 CloudKit 同步，本地数据被镜像到 iCloud，与 iCloud 开关的语义冲突。
    static let localModelConfiguration: ModelConfiguration = {
        let groupIdentifier = "group.com.aether.app"
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let storeURL = groupURL.appendingPathComponent("Aether.sqlite")
            return ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        }
        return ModelConfiguration(isStoredInMemoryOnly: false, cloudKitDatabase: .none)
    }()

    /// iCloud 同步配置：CloudKit 自动同步，container identifier 由 entitlements
    /// 中的 com.apple.developer.icloud-container-identifiers 指定（iCloud.com.aether.app）。
    ///
    /// Task 14.3: 冲突解决采用 "last writer wins"（多设备并发写同一记录时以最后一次写入为准）；
    /// SwiftData 未公开 beforeSave 钩子，字段级合并需在 ViewModel 层显式实现。
    static let iCloudModelConfiguration = ModelConfiguration(cloudKitDatabase: .automatic)

    struct StoreResolution {
        let container: ModelContainer
        let configuration: ModelConfiguration
        let backend: StoreBackend
    }

    /// 解析实际存储后端：iCloud 开关开启时先验证 CloudKit 容器是否可用；
    /// 失败则回退**本地持久化**（而非内存），避免用户以为正在同步、实际数据不落盘。
    ///
    /// 当前 SwiftData schema 已按 CloudKit 约束建模（属性可选或有默认值、关系可选且有 inverse、
    /// 无唯一约束，由 CloudKitSchemaCompatibilityTests 守护），此处的回退分支用于 iCloud 账号
    /// 未登录、CloudKit 容器不可用等运行时故障；UI 通过 `isICloudSyncFallingBackToLocal` 提示。
    ///
    /// 最终兜底：本地持久化也失败时降级 in-memory（App 可运行但数据不持久化）；
    /// in-memory 也失败（系统级 SwiftData 故障）则上报 CrashReportService 后 fatalError——
    /// SwiftUI App 启动必须返回 ModelContainer，没有它 ChatView 通过 @Environment(\.modelContext)
    /// 会立即崩溃，无法展示任何降级 UI。
    static func resolveStore(
        iCloudEnabled: Bool,
        makeContainer: (ModelConfiguration) throws -> ModelContainer
    ) -> StoreResolution {
        if iCloudEnabled {
            do {
                return StoreResolution(
                    container: try makeContainer(iCloudModelConfiguration),
                    configuration: iCloudModelConfiguration,
                    backend: .cloudKit
                )
            } catch {
                Logger.app.error("CloudKit 容器创建失败，回退本地存储: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            return StoreResolution(
                container: try makeContainer(localModelConfiguration),
                configuration: localModelConfiguration,
                backend: .local
            )
        } catch {
            Logger.app.error("持久化 ModelContainer 创建失败，降级到 in-memory 模式: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return StoreResolution(
                container: try makeContainer(configuration),
                configuration: configuration,
                backend: .inMemory
            )
        } catch {
            CrashReportService.shared.reportException(
                NSError(domain: "AetherApp", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create in-memory ModelContainer: \(error)"
                ])
            )
            fatalError("Failed to create in-memory ModelContainer (SwiftData 系统级故障): \(error)")
        }
    }

    /// 本进程的存储解析结果（首次访问时创建，App 生命周期内复用）。
    private static let resolvedStore = resolveStore(iCloudEnabled: isICloudSyncEnabled) {
        try makeModelContainer(configuration: $0)
    }

    /// 预构建的 ModelContainer（见 `resolvedStore` 的解析策略）。
    static var sharedModelContainer: ModelContainer { resolvedStore.container }

    /// 本进程实际生效的存储配置。iCloud 不可用时为本地配置。
    static var activeModelConfiguration: ModelConfiguration { resolvedStore.configuration }

    /// 本进程实际生效的存储后端。
    static var storeBackend: StoreBackend { resolvedStore.backend }

    /// 用户开启了 iCloud 同步，但本次启动已回退本地存储（数据不会同步）。
    static var isICloudSyncFallingBackToLocal: Bool {
        isICloudSyncEnabled && resolvedStore.backend == .local
    }

    /// UITest 数据重置：创建独立的 ModelContainer（使用本进程实际生效的存储配置），
    /// 调用 ChatStorage.wipeAllData() 清空所有 SwiftData 数据。
    func wipeAllDataForUITest() {
        do {
            let container = try AetherApp.makeModelContainer(configuration: AetherApp.activeModelConfiguration)
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

        // v1.1 Phase C: 注入 ToolRegistry 到 PluginManager，使插件工具可注册到工具注册中心
        PluginToolRegistryBridge.setup()

        // 端侧推理 provider 依赖 MLX、保留在 App target，启动时注入供 ModelProviderFactory.make(.onDevice) 使用
        ModelProviderFactory.onDeviceProviderFactory = { OfflineLLMProvider() }
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
