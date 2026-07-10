import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Day 18: Spotlight 索引管理。将会话索引到 Spotlight，支持系统搜索直接打开对应会话。
/// 索引内容：标题、最后一条消息内容、最近更新时间（用 createdAt 兜底，因 Conversation 无 updatedAt 字段）。
enum SpotlightIndexer {
    /// 索引单个会话到 Spotlight。
    /// - Parameter conversation: 待索引的会话
    static func index(_ conversation: Conversation) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = conversation.title
        attributes.contentDescription = conversation.messages.last?.content
        // Conversation 仅有 createdAt（无 updatedAt），用 createdAt 作为最近使用时间
        attributes.lastUsedDate = conversation.createdAt

        let item = CSSearchableItem(
            uniqueIdentifier: conversation.id.uuidString,
            domainIdentifier: "com.aether.conversations",
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error { print("Spotlight index error: \(error)") }
        }
    }

    /// 从 Spotlight 移除指定会话的索引。
    /// - Parameter conversationId: 会话唯一标识
    static func removeIndex(conversationId: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [conversationId.uuidString]
        ) { _ in }
    }

    /// 清空所有以太会话索引。
    static func clearAll() {
        CSSearchableIndex.default().deleteAllSearchableItems { _ in }
    }
}
