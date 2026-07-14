import Foundation

/// 平台无关的会话数据传输对象
///
/// 跨平台（iOS/macOS/Android/Windows）统一的会话契约，
/// 由各平台的 Repository 适配器在平台模型（如 SwiftData @Model）与 DTO 之间转换。
public struct ConversationDTO: Sendable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var systemPrompt: String
    public var parentConversationId: UUID?
    public var parentMessageId: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastMessagePreview: String
    public var isPinned: Bool
    public var unreadCount: Int
    public var order: Int

    public init(
        id: UUID,
        title: String,
        systemPrompt: String = "你是一个有帮助的AI助手。",
        parentConversationId: UUID? = nil,
        parentMessageId: UUID? = nil,
        createdAt: Date,
        updatedAt: Date,
        lastMessagePreview: String = "",
        isPinned: Bool = false,
        unreadCount: Int = 0,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.parentConversationId = parentConversationId
        self.parentMessageId = parentMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessagePreview = lastMessagePreview
        self.isPinned = isPinned
        self.unreadCount = unreadCount
        self.order = order
    }
}
