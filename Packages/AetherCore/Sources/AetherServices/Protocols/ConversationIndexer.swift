import AetherFoundation
import Foundation

/// 会话索引协议，各平台独立实现（iOS/macOS: CoreSpotlight, Android/Windows: 各自方案）
/// 解耦 ChatStorage 对 SpotlightIndexer 的隐式依赖
public protocol ConversationIndexer: Sendable {
    /// 索引或更新单个会话
    /// - Parameter conversation: 平台无关的会话数据传输对象
    func index(conversation: ConversationIndexDTO) async

    /// 从索引中移除指定会话
    /// - Parameter conversationId: 会话唯一标识
    func remove(conversationId: UUID) async

    /// 清空所有会话索引
    func removeAll() async
}

/// 平台无关的会话索引数据传输对象
/// 将 SwiftData @Model Conversation 的索引相关字段提取为纯值类型，
/// 使 ChatStorage 可以通过协议调用而不直接依赖 CoreSpotlight
public struct ConversationIndexDTO: Sendable, Codable {
    /// 会话唯一标识
    public let id: UUID
    /// 会话标题
    public var title: String
    /// 最后一条消息内容（用于 Spotlight contentDescription）
    public var lastMessageContent: String?
    /// 创建时间（用于 Spotlight lastUsedDate）
    public var createdAt: Date

    public init(id: UUID, title: String, lastMessageContent: String?, createdAt: Date) {
        self.id = id
        self.title = title
        self.lastMessageContent = lastMessageContent
        self.createdAt = createdAt
    }
}
