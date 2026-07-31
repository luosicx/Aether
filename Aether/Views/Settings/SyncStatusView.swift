#if os(iOS) || os(macOS)
import SwiftUI
import AetherDesign
import os

/// v2.0: iCloud 同步状态视图。
///
/// 展示同步状态、上次同步时间、待同步条目数、冲突数，提供同步开关与手动触发同步按钮。
/// 通过 `@StateObject` 订阅 `CloudKitSyncManager.shared` 的 Combine 发布状态。
///
/// 设计令牌：使用 AetherDesign 中的颜色（aetherPurple / starlight / deepSpace / electricBlue）
/// 与间距（Spacing）。
struct SyncStatusView: View {
    @StateObject private var syncManager = CloudKitSyncManager.shared

    /// iCloud 同步开关（读写 AetherApp.iCloudSyncEnabledKey，切换后需重启 App 生效）
    @State private var iCloudSyncEnabled: Bool = AetherApp.isICloudSyncEnabled
    /// 同步切换后提示重启 App
    @State private var showRestartAlert: Bool = false

    var body: some View {
        Form {
            syncToggleSection
            statusSection
            actionSection
        }
        .formStyle(.grouped)
        .tint(Color.aetherPurple)
        .foregroundStyle(Color.starlight)
        .scrollContentBackground(.hidden)
        .background(Color.deepSpace.ignoresSafeArea())
        .navigationTitle("iCloud 同步")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("SyncStatusView")
        .alert(NSLocalizedString("需要重启 App", comment: "iCloud 同步切换重启提示标题"),
               isPresented: $showRestartAlert) {
            Button(NSLocalizedString("好", comment: "确认按钮"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("iCloud 同步设置已更新，请重启 App 以应用新的存储配置。",
                                   comment: "iCloud 同步重启提示正文"))
        }
    }

    // MARK: - Section: 同步开关

    @ViewBuilder
    private var syncToggleSection: some View {
        Section {
            Toggle("启用 iCloud 同步", isOn: Binding(
                get: { iCloudSyncEnabled },
                set: { newValue in
                    iCloudSyncEnabled = newValue
                    AetherApp.setICloudSyncEnabled(newValue)
                    if newValue {
                        // 启用时记录一次时间戳作为占位「上次同步时间」
                        AetherApp.lastICloudSyncDate = Date()
                    }
                    showRestartAlert = true
                }
            ))
            .accessibilityLabel("启用 iCloud 同步")
            .accessibilityHint("开启后跨设备同步对话数据，需重启 App 生效")
            .accessibilityIdentifier("syncStatusToggle")

            HStack(spacing: Spacing.md) {
                Text("CloudKit 容器", comment: "")
                Spacer()
                Text(AetherApp.cloudKitContainerIdentifier)
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }
            .accessibilityLabel("CloudKit 容器")
            .accessibilityHint("显示当前使用的 CloudKit 容器标识")
            .accessibilityIdentifier("syncStatusContainerRow")
        } header: {
            Text("同步开关", comment: "")
        } footer: {
            Text("开启后对话将通过 iCloud CloudKit 在所有登录同一 Apple ID 的设备间同步。切换开关后请重启 App 生效。",
                 comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Section: 同步状态

    @ViewBuilder
    private var statusSection: some View {
        Section {
            // 同步状态
            HStack(spacing: Spacing.md) {
                Text("同步状态", comment: "")
                Spacer()
                if syncManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("同步中", comment: "")
                        .foregroundStyle(Color.electricBlue)
                } else if iCloudSyncEnabled {
                    Text("已启用", comment: "")
                        .foregroundStyle(.green)
                } else {
                    Text("未启用", comment: "")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("同步状态")
            .accessibilityHint("显示当前 iCloud 同步状态")
            .accessibilityIdentifier("syncStatusStateRow")

            // 上次同步时间
            HStack(spacing: Spacing.md) {
                Text("上次同步时间", comment: "")
                Spacer()
                Text(lastSyncText)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("上次同步时间")
            .accessibilityHint("显示上次 iCloud 同步的时间")
            .accessibilityIdentifier("syncStatusLastSyncRow")

            // 待同步条目数
            HStack(spacing: Spacing.md) {
                Text("待同步条目", comment: "")
                Spacer()
                Text("\(syncManager.pendingChangesCount)")
                    .foregroundStyle(syncManager.pendingChangesCount > 0 ? Color.aetherPurple : .secondary)
                    .monospacedDigit()
            }
            .accessibilityLabel("待同步条目数")
            .accessibilityHint("显示尚未上传到 CloudKit 的本地变更数")
            .accessibilityIdentifier("syncStatusPendingRow")

            // 冲突数
            HStack(spacing: Spacing.md) {
                Text("冲突数", comment: "")
                Spacer()
                Text("\(syncManager.conflictCount)")
                    .foregroundStyle(syncManager.conflictCount > 0 ? Color.red : .secondary)
                    .monospacedDigit()
            }
            .accessibilityLabel("冲突数")
            .accessibilityHint("显示 CloudKit 同步冲突累计计数")
            .accessibilityIdentifier("syncStatusConflictRow")
        } header: {
            Text("同步状态", comment: "")
        } footer: {
            Text("状态由 NSPersistentCloudKitContainer 同步事件实时更新。冲突采用 last writer wins 策略。",
                 comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - Section: 操作

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button {
                Task { await syncManager.triggerSync() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if syncManager.isSyncing {
                        ProgressView().controlSize(.small)
                    }
                    Text(syncManager.isSyncing ? "同步中..." : "立即同步", comment: "")
                }
            }
            .disabled(!iCloudSyncEnabled || syncManager.isSyncing)
            .accessibilityLabel("立即同步")
            .accessibilityHint("手动触发 iCloud 同步")
            .accessibilityIdentifier("syncStatusTriggerButton")
        } header: {
            Text("操作", comment: "")
        } footer: {
            Text("手动触发后会尝试同步本地变更到 iCloud。实际同步由系统自动调度。", comment: "")
                .font(.captionAI)
        }
    }

    // MARK: - 辅助

    /// 上次同步时间可读文案
    private var lastSyncText: String {
        guard let date = syncManager.lastSyncDate else {
            return NSLocalizedString("从未", comment: "")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
#endif
