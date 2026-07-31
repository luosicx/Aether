#if os(iOS) || os(macOS)
import Foundation
import Combine
import CoreData
import CloudKit
import os

// MARK: - Logger

private extension Logger {
    /// v2.0: iCloud 同步模块日志（与 Logger+Modules.swift 同 subsystem，category=sync）
    static let sync = Logger(subsystem: "com.aether.app", category: "sync")
}

// MARK: - 通知名

extension Notification.Name {
    /// v2.0: 用户手动触发 CloudKit 同步（由 `CloudKitSyncManager.triggerSync` 发出，
    /// 持久化层可监听此通知并执行 `context.save()` 以促使 NSPersistentCloudKitContainer 调度导出）
    static let cloudKitSyncRequested = Notification.Name("aether.cloudkit.syncRequested")
}

// MARK: - CloudKitSyncManager

/// v2.0: iCloud 同步增强模块——CloudKit 同步状态管理单例。
///
/// 职责：
/// - 维护并发布同步状态（`lastSyncDate` / `pendingChangesCount` / `conflictCount` / `isSyncing`）
/// - 监听 `NSPersistentCloudKitContainer.eventChangedNotification`，从 CloudKit 同步事件中
///   提取同步开始/结束、上传/下载结果与冲突错误，实时更新状态
/// - 提供手动触发同步入口 `triggerSync()`
/// - 与 `AetherApp+Shared.swift` 中的 `iCloudSyncEnabledKey` / `lastICloudSyncDateKey` 协同：
///   同步完成后将 `lastSyncDate` 回写 UserDefaults，兼容 v1 Task 14 占位实现
///
/// 并发说明：
/// - 标记 `@MainActor` + `ObservableObject` + `@Published`，便于 SwiftUI 视图通过 Combine 直接订阅状态变化
/// - 观察者 token 使用 `nonisolated(unsafe)` 存储，便于在 `deinit` 中安全移除
///   （`deinit` 非 `@MainActor` 隔离，无法访问隔离属性）
///
/// 平台可用性：
/// - 仅 iOS / macOS 编译（visionOS / watchOS 暂不支持 NSPersistentCloudKitContainer 同步）
@MainActor
final class CloudKitSyncManager: ObservableObject {
    /// 单例。App 启动时初始化，全生命周期持有。生产环境请使用 `.shared`。
    static let shared = CloudKitSyncManager()

    // MARK: - Published 同步状态

    /// 上次成功同步时间（同步完成或手动触发后更新，并持久化到 UserDefaults）
    @Published private(set) var lastSyncDate: Date?

    /// 待同步条目数（尚未上传到 CloudKit 的本地变更；由 `updatePendingCount` 或导出事件维护）
    @Published private(set) var pendingChangesCount: Int = 0

    /// 冲突数（CloudKit 反馈的冲突累计计数；`recordConflict` 递增）
    @Published private(set) var conflictCount: Int = 0

    /// 是否正在同步
    @Published private(set) var isSyncing: Bool = false

    // MARK: - 私有

    /// CloudKit 事件观察者 token。`nonisolated(unsafe)` 以便 `deinit` 移除
    /// （`deinit` 无法访问 `@MainActor` 隔离属性；实例析构时无并发访问，安全）
    private nonisolated(unsafe) var eventObserver: NSObjectProtocol?

    /// 内部初始化。生产环境使用 `.shared`；测试可直接构造以获取干净状态。
    init() {
        // 与 v1 Task 14 占位实现兼容：从 UserDefaults 恢复上次同步时间
        lastSyncDate = AetherApp.lastICloudSyncDate
        startObservingCloudKitEvents()
        Logger.sync.notice("CloudKitSyncManager 已初始化")
    }

    deinit {
        // deinit 非 @MainActor 隔离；eventObserver 已标记 nonisolated(unsafe) 可在此访问
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 公共 API

    /// 手动触发同步。
    ///
    /// NSPersistentCloudKitContainer 无公开 API 强制立即同步；此处发送 `.cloudKitSyncRequested`
    /// 通知（持久化层可监听并执行 `context.save()` 以促使 CloudKit 调度导出），并记录本次触发时间。
    /// 实际同步进度由 `eventChangedNotification` 回调更新。
    ///
    /// 已在同步中时跳过重复触发。
    func triggerSync() async {
        guard !isSyncing else {
            Logger.sync.notice("triggerSync: 同步进行中，跳过重复触发")
            return
        }
        beginSync()
        Logger.sync.notice("triggerSync: 手动触发 CloudKit 同步")
        NotificationCenter.default.post(name: .cloudKitSyncRequested, object: nil)
        let now = Date()
        lastSyncDate = now
        AetherApp.lastICloudSyncDate = now
        // 让出主线程一帧，允许 UI 观察到 isSyncing=true 状态
        await Task.yield()
        finishSync()
    }

    /// 记录一次冲突（递增 `conflictCount`）。
    func recordConflict() {
        conflictCount += 1
        Logger.sync.error("CloudKit 同步冲突已记录，累计冲突数=\(self.conflictCount, privacy: .public)")
    }

    /// 更新待同步条目数（负值会被截断为 0）。
    func updatePendingCount(_ count: Int) {
        pendingChangesCount = max(0, count)
        Logger.sync.debug("updatePendingCount: 待同步条目数=\(self.pendingChangesCount, privacy: .public)")
    }

    // MARK: - 内部状态切换（亦供测试与事件回调使用）

    /// 标记同步开始
    internal func beginSync() {
        isSyncing = true
    }

    /// 标记同步结束
    internal func finishSync() {
        isSyncing = false
    }

    // MARK: - CloudKit 事件监听

    /// 注册 `NSPersistentCloudKitContainer.eventChangedNotification` 监听
    private func startObservingCloudKitEvents() {
        guard eventObserver == nil else { return }
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // queue: .main 保证回调在主队列；通过 MainActor.assumeIsolated 桥接到 @MainActor 隔离
            MainActor.assumeIsolated {
                self?.handleCloudKitEvent(notification)
            }
        }
    }

    /// 处理 CloudKit 同步事件，更新状态
    private func handleCloudKitEvent(_ notification: Notification) {
        // 使用字符串 key 避免 SDK 版本差异（NSPersistentCloudKitContainer.Event.NotificationKey.event 的原始值即 "event"）
        guard let event = notification.userInfo?["event"]
                as? NSPersistentCloudKitContainer.Event else {
            return
        }

        // 事件进行中（endDate 为 nil）：标记同步开始
        if event.endDate == nil {
            beginSync()
            Logger.sync.debug("CloudKit 事件开始: type=\(event.type.rawValue, privacy: .public)")
            return
        }

        // 事件结束：用 error==nil 判断成功（避免使用部分 SDK 不可用的 Event.success）
        if let error = event.error {
            Logger.sync.error("CloudKit 事件失败: type=\(event.type.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            // CKError 冲突检测：
            // - serverRecordChanged: 服务端记录已变更，触发 last writer wins 冲突
            // - batchRequestFailed: 批量请求失败（可能含冲突）
            if let ckError = error as? CKError,
               ckError.code == CKError.Code.serverRecordChanged || ckError.code == CKError.Code.batchRequestFailed {
                recordConflict()
            }
        } else {
            lastSyncDate = event.endDate
            AetherApp.lastICloudSyncDate = event.endDate
            // 导出成功：减少待同步条目
            if event.type == .export, pendingChangesCount > 0 {
                pendingChangesCount = max(0, pendingChangesCount - 1)
            }
            Logger.sync.notice("CloudKit 事件成功: type=\(event.type.rawValue, privacy: .public)")
        }

        finishSync()
    }
}
#endif
