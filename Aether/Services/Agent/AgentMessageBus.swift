import Foundation

/// v1.1 Phase B: Agent 消息总线。
///
/// 基于 `AsyncStream` 实现 pub/sub 模式的消息总线，支持跨 Agent 通信：
/// - 任务委派（taskDelegation）：将子任务委派给指定 Agent
/// - 结果回传（resultDelivery）：将执行结果回传给委派发起方
/// - 状态更新（statusUpdate）：广播 Agent 状态变化
///
/// 设计要点：
/// - `actor` 隔离：天然线程安全，无需额外锁
/// - 每个 topic 维护独立的 `AsyncStream`，多订阅者独立消费
/// - 订阅者通过 `Continuation` 接收消息，订阅结束自动清理
/// - topic 使用字符串标识，约定格式：`agent.<UUID>` 或 `task.<UUID>`
actor AgentMessageBus {

    /// 单个订阅的句柄（用于取消订阅）
    struct Subscription: Hashable, Sendable {
        let id: UUID
    }

    /// topic → 订阅者 continuations 映射
    private var subscribers: [String: [UUID: AsyncStream<AgentMessage>.Continuation]] = [:]

    /// 创建消息总线
    init() {}

    /// 发布消息到指定 topic
    ///
    /// 所有订阅该 topic 的订阅者都会收到消息副本。
    /// 若该 topic 当前无订阅者，消息将被丢弃（fire-and-forget 语义）。
    /// - Parameters:
    ///   - topic: 消息主题（约定格式：`agent.<UUID>` 或 `task.<UUID>`）
    ///   - message: 待发布的消息
    func publish(topic: String, message: AgentMessage) async {
        guard let subs = subscribers[topic] else { return }
        for (_, continuation) in subs {
            continuation.yield(message)
        }
    }

    /// 订阅指定 topic 的消息流
    ///
    /// 返回的 `AsyncStream` 在订阅者停止迭代或被取消时自动清理。
    /// 订阅者只能收到订阅之后发布的消息（不保留历史）。
    /// - Parameter topic: 消息主题
    /// - Returns: 消息异步流
    func subscribe(topic: String) -> AsyncStream<AgentMessage> {
        let subscriptionID = UUID()
        let stream = AsyncStream<AgentMessage> { continuation in
            self.addSubscriber(topic: topic, id: subscriptionID, continuation: continuation)
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.removeSubscriber(topic: topic, id: subscriptionID)
                }
            }
        }
        return stream
    }

    /// 获取指定 topic 的当前订阅者数量（用于测试与诊断）
    /// - Parameter topic: 消息主题
    /// - Returns: 订阅者数量
    func subscriberCount(topic: String) -> Int {
        subscribers[topic]?.count ?? 0
    }

    /// 清空所有订阅者（用于测试重置）
    func reset() {
        for (_, subs) in subscribers {
            for (_, continuation) in subs {
                continuation.finish()
            }
        }
        subscribers.removeAll()
    }

    // MARK: - 私有

    /// 添加订阅者（必须在 actor 上下文中调用）
    private func addSubscriber(topic: String, id: UUID, continuation: AsyncStream<AgentMessage>.Continuation) {
        if subscribers[topic] == nil {
            subscribers[topic] = [:]
        }
        subscribers[topic]?[id] = continuation
    }

    /// 移除订阅者（必须在 actor 上下文中调用）
    private func removeSubscriber(topic: String, id: UUID) {
        subscribers[topic]?.removeValue(forKey: id)
        if subscribers[topic]?.isEmpty == true {
            subscribers.removeValue(forKey: topic)
        }
    }
}

/// v1.1 Phase B: Agent 间传递的消息类型
enum AgentMessage: Sendable {
    /// 任务委派：将子任务委派给目标 Agent 执行
    case taskDelegation(subTaskId: UUID, from: UUID, to: UUID, description: String)
    /// 结果回传：将执行结果回传给委派发起方
    case resultDelivery(subTaskId: UUID, from: UUID, to: UUID, result: String)
    /// 状态更新：广播 Agent 状态变化
    case statusUpdate(agentId: UUID, status: AgentStatus)
}
