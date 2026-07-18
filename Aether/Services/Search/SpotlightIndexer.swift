import AetherServices
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os

/// Day 18: Spotlight 索引管理。将会话索引到 Spotlight，支持系统搜索直接打开对应会话。
/// 索引内容：标题、最后一条消息内容、最近更新时间（用 createdAt 兜底，因 Conversation 无 updatedAt 字段）。
/// Task 1.7: 重构为 ConversationIndexer 协议实现，解耦 ChatStorage 对 CoreSpotlight 的直接依赖。
final class SpotlightIndexer: ConversationIndexer {
    static let shared = SpotlightIndexer()

    private init() {
        // 单例模式：外部不可创建实例
    }

    /// 索引或更新单个会话
    /// - Parameter conversation: 平台无关的会话数据传输对象
    func index(conversation: ConversationIndexDTO) async {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = conversation.title
        attributes.contentDescription = conversation.lastMessageContent
        // Conversation 仅有 createdAt（无 updatedAt），用 createdAt 作为最近使用时间
        attributes.lastUsedDate = conversation.createdAt

        let item = CSSearchableItem(
            uniqueIdentifier: conversation.id.uuidString,
            domainIdentifier: "com.aether.conversations",
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error { Logger.storage.error("Spotlight index error: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// 从索引中移除指定会话
    /// - Parameter conversationId: 会话唯一标识
    func remove(conversationId: UUID) async {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [conversationId.uuidString]
        ) { _ in
            // 删除完成回调，错误可忽略（下次启动会重新索引）
        }
    }

    /// 清空所有以太会话索引
    func removeAll() async {
        CSSearchableIndex.default().deleteAllSearchableItems { _ in
            // 全部删除完成回调，错误可忽略（下次启动会重新索引）
        }
    }
}
