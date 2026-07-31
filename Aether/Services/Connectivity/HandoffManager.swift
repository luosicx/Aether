import Foundation
import os

#if os(iOS) || os(macOS)

/// Handoff activity type 常量。
/// 用于 NSUserActivity 的 activityType 标识，区分不同 Handoff 场景。
enum HandoffActivityTypes {
    /// 聊天连续对话 activity type。
    /// userInfo 携带 conversationId / lastMessageId / scrollPosition，供目标设备接续。
    static let chatContinue = "com.aether.chat.continue"
}

/// Handoff 接续负载：从 NSUserActivity.userInfo 解析出的连续对话状态。
/// 值类型，Sendable，可跨 actor 传递。
struct HandoffPayload: Sendable, Equatable {
    /// 当前会话 ID
    let conversationId: UUID
    /// 最后可见消息 ID（用于恢复滚动位置对齐），可能为 nil
    let lastMessageId: UUID?
    /// 滚动位置（0.0 ~ 1.0，表示消息列表相对位置）
    let scrollPosition: Double
}

/// HandoffManager：管理 NSUserActivity 的单例，支持 Handoff 连续对话。
///
/// v2.0 Handoff 连续对话模块。
///
/// 设计要点：
/// - 单例 `shared`，@MainActor 隔离，确保 NSUserActivity 在主线程读写
/// - `becomeCurrent` 创建并广播当前会话的 NSUserActivity，供其他设备接续
/// - `handleContinueActivity` 解析接续 activity，返回 HandoffPayload 供 UI 恢复
/// - `invalidate` 作废当前 activity（如会话关闭、App 退到后台不再广播）
///
/// Swift 6 严格并发：NSUserActivity 非 Sendable，通过 @MainActor 隔离保证线程安全。
@MainActor
final class HandoffManager {
    /// 单例
    static let shared = HandoffManager()

    /// 当前 NSUserActivity（已 becomeCurrent 广播中），nil 表示无活跃 activity
    private(set) var currentActivity: NSUserActivity?

    /// 私有初始化，强制使用单例
    private init() {}

    /// 创建并广播 NSUserActivity，记录当前会话的连续对话状态。
    /// - Parameters:
    ///   - conversationId: 当前会话 ID
    ///   - lastMessageId: 最后可见消息 ID（可选，用于恢复滚动对齐）
    ///   - scrollPosition: 滚动位置（0.0 ~ 1.0）
    func becomeCurrent(conversationId: UUID, lastMessageId: UUID?, scrollPosition: Double) {
        // 作废已有 activity，避免多个 activity 同时 current
        if let existing = currentActivity {
            existing.invalidate()
        }

        let activity = NSUserActivity(activityType: HandoffActivityTypes.chatContinue)
        activity.title = "Aether Chat"
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false

        var userInfo: [String: Any] = [
            "conversationId": conversationId.uuidString,
            "scrollPosition": scrollPosition,
        ]
        if let lastMessageId {
            userInfo["lastMessageId"] = lastMessageId.uuidString
        }
        activity.userInfo = userInfo

        activity.becomeCurrent()
        currentActivity = activity

        let lastMessageIdStr = lastMessageId?.uuidString ?? "nil"
        Logger.network.info(
            "Handoff becomeCurrent: conversationId=\(conversationId.uuidString, privacy: .public) lastMessageId=\(lastMessageIdStr, privacy: .public) scrollPosition=\(scrollPosition, privacy: .public)"
        )
    }

    /// 作废当前 activity，停止广播。
    func invalidate() {
        currentActivity?.invalidate()
        currentActivity = nil
        Logger.network.info("Handoff invalidate: cleared current activity")
    }

    /// 处理接续 activity，解析为 HandoffPayload。
    /// - Parameter activity: 系统通过 `onContinueUserActivity` 投递的 NSUserActivity
    /// - Returns: 解析成功返回 HandoffPayload；activityType 不匹配或缺少必要字段返回 nil
    func handleContinueActivity(_ activity: NSUserActivity) -> HandoffPayload? {
        guard activity.activityType == HandoffActivityTypes.chatContinue else {
            Logger.network.error("Handoff activityType mismatch: \(activity.activityType, privacy: .public)")
            return nil
        }

        guard let userInfo = activity.userInfo,
              let conversationIdStr = userInfo["conversationId"] as? String,
              let conversationId = UUID(uuidString: conversationIdStr) else {
            Logger.network.error("Handoff missing or invalid conversationId in userInfo")
            return nil
        }

        let scrollPosition = userInfo["scrollPosition"] as? Double ?? 0.0
        let lastMessageId: UUID?
        if let lastMessageIdStr = userInfo["lastMessageId"] as? String {
            lastMessageId = UUID(uuidString: lastMessageIdStr)
        } else {
            lastMessageId = nil
        }

        let lastMessageIdLogStr = lastMessageId?.uuidString ?? "nil"
        Logger.network.info(
            "Handoff continue: conversationId=\(conversationId.uuidString, privacy: .public) lastMessageId=\(lastMessageIdLogStr, privacy: .public) scrollPosition=\(scrollPosition, privacy: .public)"
        )

        return HandoffPayload(
            conversationId: conversationId,
            lastMessageId: lastMessageId,
            scrollPosition: scrollPosition
        )
    }
}

#endif
