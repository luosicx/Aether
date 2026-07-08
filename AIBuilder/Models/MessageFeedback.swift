import Foundation
import SwiftData

/// 持久化用户对 assistant 消息的反馈（点赞/踩），用于反馈闭环调整 RAG chunk 权重
@Model
final class MessageFeedback {
    /// 唯一标识
    var id: UUID
    /// 关联的 ChatMessage.id
    var messageId: UUID
    /// 是否为点赞（true=赞，false=踩）
    var isPositive: Bool
    /// 创建时间
    var createdAt: Date
    /// 反向关联所属 Conversation
    var conversation: Conversation?

    init(messageId: UUID, isPositive: Bool) {
        self.id = UUID()
        self.messageId = messageId
        self.isPositive = isPositive
        self.createdAt = Date()
        self.conversation = nil
    }
}
