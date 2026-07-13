import Foundation

#if os(iOS)
import WatchConnectivity

/// Day 17: watchOS 与 iOS 通信服务，管理活跃会话同步与快速对话消息。
///
/// 设计要点：
/// - 单例 `shared`，App 启动时调用 `activate()` 激活 WCSession
/// - 通过 NotificationCenter 广播接收到的消息，便于 ViewModel 监听
/// - 仅 iOS 端实现 `sessionDidBecomeInactive` / `sessionDidDeactivate`
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    /// 单例
    static let shared = WatchConnectivityService()

    /// 当前活跃会话 ID（由 watchOS 端同步或本端设置）
    var activeConversationId: UUID?

    /// 私有初始化，强制使用单例
    private override init() {
        super.init()
    }

    /// 激活 WCSession。设备不支持时静默返回。
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 向 watchOS 同步当前活跃会话 ID。
    /// - Parameter id: 活跃会话 ID
    func sendActiveConversation(_ id: UUID) {
        activeConversationId = id
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(["action": "activeConversation", "id": id.uuidString], replyHandler: nil)
    }

    /// 向 watchOS 发送快速对话消息。
    /// - Parameter message: 用户输入的快速对话文本
    func sendQuickChat(_ message: String) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(["action": "quickChat", "message": message], replyHandler: nil)
    }

    // MARK: - WCSessionDelegate

    /// WCSession 激活完成回调
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error)")
        }
    }

    /// 接收到 watchOS 发来的实时消息，按 action 分发到 NotificationCenter
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }

    /// Day 17: 接收到 watchOS 发来的后台 userInfo（transferUserInfo 投递），按 action 分发到 NotificationCenter。
    /// 即使 iOS App 不在前台，系统也会在下次启动/唤醒时回调此方法。
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncomingMessage(userInfo)
    }

    /// 统一处理收到的消息（实时 + 后台 userInfo 共用），按 action 分发到 NotificationCenter
    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        switch action {
        case "activeConversation":
            if let idStr = message["id"] as? String, let id = UUID(uuidString: idStr) {
                activeConversationId = id
                NotificationCenter.default.post(name: .wcActiveConversationChanged, object: id)
            }
        case "quickChat":
            if let msg = message["message"] as? String {
                NotificationCenter.default.post(name: .wcQuickChatReceived, object: msg)
            }
        default:
            break
        }
    }

    /// 可达性变化时通知监听方
    func sessionReachabilityDidChange(_ session: WCSession) {
        NotificationCenter.default.post(name: .wcReachabilityChanged, object: session.isReachable)
    }

    // MARK: - iOS only

    /// iOS 专属：会话变为非活跃（如切换到其他设备）
    func sessionDidBecomeInactive(_ session: WCSession) {
        // 空实现，子类可按需扩展
    }

    /// iOS 专属：会话失效后重新激活（系统要求）
    func sessionDidDeactivate(_ session: WCSession) {
        // 重新激活以连接到新配对的 watch
        WCSession.default.activate()
    }
}
#endif

// MARK: - 通知名扩展（跨平台：WatchConnectivityService 仅 iOS 编译，但通知名需在 macOS 端可读以便 ChatViewModel 编译）
extension Notification.Name {
    /// 活跃会话变更通知（object 为新的会话 UUID）
    static let wcActiveConversationChanged = Notification.Name("wcActiveConversationChanged")
    /// 收到快速对话消息通知（object 为消息文本）
    static let wcQuickChatReceived = Notification.Name("wcQuickChatReceived")
    /// watchOS 可达性变更通知（object 为 Bool 是否可达）
    static let wcReachabilityChanged = Notification.Name("wcReachabilityChanged")
}
