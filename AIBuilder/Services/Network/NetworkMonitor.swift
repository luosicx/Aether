import Foundation
import Network

/// Day 16: 网络状态枚举。覆盖离线、在线、蜂窝、Wi-Fi 四种状态。
enum NetworkStatus: Sendable, Equatable {
    case online
    case offline
    case cellular
    case wifi
}

/// Day 16: 网络监控 actor。基于 NWPathMonitor 监听设备网络状态变化，
/// 用于断网时自动切换到端侧推理、联网后切回云端。
/// actor 隔离保证并发安全，statusStream 暴露状态变化流供外部订阅。
actor NetworkMonitor {
    /// 单例，全局共享一个监控器
    static let shared = NetworkMonitor()

    /// NWPathMonitor 实例（非 Sendable，受 actor 隔离保护）
    private let monitor: NWPathMonitor
    /// 当前网络状态（初始 offline，start 后由 pathUpdateHandler 更新）
    private(set) var currentStatus: NetworkStatus = .offline
    /// 所有活跃的订阅 continuation，状态变化时逐一 yield
    private var continuations: [AsyncStream<NetworkStatus>.Continuation] = []
    /// 是否已启动监控（避免重复 start 导致 NWPathMonitor 异常）
    private var started = false

    init() {
        monitor = NWPathMonitor()
    }

    /// 启动网络监控。已启动时直接返回，避免重复调用。
    func start() {
        guard !started else { return }
        started = true
        // pathUpdateHandler 在 monitor 的 queue 上回调，需 hop 到 actor 更新状态
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            Task { await self.updateStatus(path) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// 根据 NWPath 更新当前状态，并通知所有订阅者。
    private func updateStatus(_ path: NWPath) {
        let newStatus: NetworkStatus
        if path.status != .satisfied {
            newStatus = .offline
        } else if path.usesInterfaceType(.wifi) {
            newStatus = .wifi
        } else if path.usesInterfaceType(.cellular) {
            newStatus = .cellular
        } else {
            newStatus = .online
        }
        currentStatus = newStatus
        for continuation in continuations {
            continuation.yield(newStatus)
        }
    }

    /// 订阅网络状态变化流。订阅时立即 yield 一次当前状态。
    /// - Returns: 网络状态变化 AsyncStream
    func statusStream() -> AsyncStream<NetworkStatus> {
        AsyncStream { continuation in
            continuations.append(continuation)
            // 立即 yield 当前状态，让订阅者无需等待变化即可获得初始值
            continuation.yield(currentStatus)
        }
    }

    /// 停止监控，结束所有订阅流。
    func stop() {
        monitor.cancel()
        started = false
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
