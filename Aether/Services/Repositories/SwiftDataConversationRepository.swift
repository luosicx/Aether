import Foundation
import SwiftData
import AetherFoundation
import AetherServices

/// SwiftData 实现的 ConversationRepository
///
/// 将 SwiftData @Model Conversation 与平台无关 ConversationDTO 桥接。
/// @MainActor 隔离，因为 ModelContext 访问需在主线程。
@MainActor
final class SwiftDataConversationRepository: ConversationRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [ConversationDTO] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let conversations = try context.fetch(descriptor)
        return conversations.map { $0.toDTO() }
    }

    func fetch(id: UUID) async throws -> ConversationDTO? {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first?.toDTO()
    }

    func save(_ conversation: ConversationDTO) async throws {
        // 查找现有会话
        let id = conversation.id
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            // 更新现有会话
            existing.title = conversation.title
            existing.systemPrompt = conversation.systemPrompt
            existing.isPinned = conversation.isPinned
            existing.unreadCount = conversation.unreadCount
            existing.order = conversation.order
            existing.parentConversationID = conversation.parentConversationId
            existing.parentMessageID = conversation.parentMessageId
        } else {
            // 创建新会话
            let newConversation = Conversation(
                title: conversation.title,
                systemPrompt: conversation.systemPrompt
            )
            newConversation.id = conversation.id
            newConversation.createdAt = conversation.createdAt
            newConversation.isPinned = conversation.isPinned
            newConversation.unreadCount = conversation.unreadCount
            newConversation.order = conversation.order
            newConversation.parentConversationID = conversation.parentConversationId
            newConversation.parentMessageID = conversation.parentMessageId
            context.insert(newConversation)
        }
        try context.save()
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id }
        )
        for conversation in try context.fetch(descriptor) {
            context.delete(conversation)
        }
        try context.save()
    }

    func search(query: String) async throws -> [ConversationDTO] {
        let lowercaseQuery = query.lowercased()
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.title.localizedStandardContains(lowercaseQuery) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDTO() }
    }

    func fetchChildren(parentId: UUID) async throws -> [ConversationDTO] {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.parentConversationID == parentId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDTO() }
    }
}

// MARK: - Conversation -> DTO 转换扩展

extension Conversation {
    /// 将 SwiftData @Model Conversation 转为平台无关 ConversationDTO
    func toDTO() -> ConversationDTO {
        let lastMessagePreview = messages.last?.content ?? ""
        // updatedAt 用最后消息时间或创建时间
        let updatedAt = messages.last?.timestamp ?? createdAt
        return ConversationDTO(
            id: id,
            title: title,
            systemPrompt: systemPrompt,
            parentConversationId: parentConversationID,
            parentMessageId: parentMessageID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessagePreview: lastMessagePreview,
            isPinned: isPinned,
            unreadCount: unreadCount,
            order: order
        )
    }
}
