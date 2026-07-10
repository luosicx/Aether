import Foundation

/// 自定义 GlobalActor，用于隔离聊天相关异步任务。
///
/// 目前仅占位，未实际应用到具体方法上。
@globalActor
struct ChatActor {
    actor Instance: Sendable {}
    static let shared = Instance()
}
