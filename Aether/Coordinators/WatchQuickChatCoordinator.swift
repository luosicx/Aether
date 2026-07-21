import Foundation

/// P2-6 Task 4: WatchQuickChatCoordinator —— Watch 快速对话消息桥接协调器
///
/// 从 ChatViewModel 抽取的 `.wcQuickChatReceived` 通知监听职责。
/// WatchConnectivityService 收到 Watch 发来的快速对话消息后广播此通知，
/// 本协调器监听该通知并通过 @MainActor 闭包回调通知 ChatViewModel 更新 `pendingWatchMessage`。
///
/// 并发边界：本类标注 `@unchecked Sendable`（与 ChatViewModel 私有 ErrorObserver 一致），
/// 使用 NSLock 包裹 token（NSObjectProtocol 非 Sendable，无法用 OSAllocatedUnfairLock<State>）。
/// init 在 @MainActor 上写 token，deinit 在 nonisolated 上下文读 token，存在跨 actor 读写，
/// 故用 NSLock 同步。
final class WatchQuickChatCoordinator: @unchecked Sendable {
    /// 通知观察者 token，用 NSLock 包裹以支持跨 actor 安全读写
    private var _token: NSObjectProtocol?
    private let lock = NSLock()

    /// 收到 Watch 快速对话消息时的回调（@MainActor 闭包，确保 pendingWatchMessage 在主线程更新）
    private let onQuickChatReceived: @MainActor (String) -> Void

    /// 观察者 token（线程安全访问），供测试断言 init 已注册观察者
    var token: NSObjectProtocol? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _token
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _token = newValue
        }
    }

    /// 构造器：注册 `.wcQuickChatReceived` 通知观察者，收到消息后通过闭包回调通知上层。
    /// - Parameter onQuickChatReceived: 收到 Watch 快速对话消息时的回调（@MainActor 闭包）。
    ///   闭包在主线程调用，参数为 Watch 发来的消息文本。
    ///   payload 为空（object 非 String）时静默忽略，与原 ChatViewModel 行为一致。
    init(onQuickChatReceived: @escaping @MainActor (String) -> Void) {
        self.onQuickChatReceived = onQuickChatReceived
        // 注册观察者：WatchConnectivityService 收到 Watch 消息后广播此通知，
        // object 字段为消息文本（String）。queue 用 OperationQueue.main 确保回调在主线程。
        self._token = NotificationCenter.default.addObserver(
            forName: .wcQuickChatReceived,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] notification in
            guard let self = self else { return }
            // payload 为空（object 非 String）时静默忽略，与原 ChatViewModel 行为一致
            guard let msg = notification.object as? String else { return }
            Task { @MainActor [weak self] in
                self?.onQuickChatReceived(msg)
            }
        }
    }

    deinit {
        if let observer = token {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
