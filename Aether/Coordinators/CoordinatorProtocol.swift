import Foundation

/// Coordinator 协议占位，便于未来扩展通用能力（如生命周期管理、日志埋点）。
///
/// P2-6: ChatViewModel 拆分为 10 个 Coordinator，每个承担单一职责，
/// 通过构造器注入到 ChatViewModel，ChatViewModel 保留为 View 入口的 Facade。
/// 所有 Coordinator SHALL 显式标注 `@MainActor` 或 `Sendable`，
/// 跨 actor 回调 SHALL 通过 `@MainActor` 闭包传递。
@MainActor
protocol Coordinator: AnyObject {}
