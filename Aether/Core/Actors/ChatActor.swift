import Foundation

/// 自定义 GlobalActor，用于隔离聊天相关异步任务。
///
/// TODO: 目前仅占位，未实际应用到具体方法上。计划后续将 ChatViewModel 中与聊天流相关的异步方法
///（如 sendMessage、streamResponse、cancelStream）标记为 @ChatActor，以隔离并发状态。
@globalActor
struct ChatActor {
    actor Instance: Sendable {}
    static let shared = Instance()
}
