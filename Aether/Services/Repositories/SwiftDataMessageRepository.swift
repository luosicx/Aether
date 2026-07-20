import Foundation
import SwiftData
import os
import AetherFoundation
import AetherServices

/// SwiftData 实现的 MessageRepository
///
/// 将 SwiftData @Model ChatMessage 与平台无关 ChatMessageDTO 桥接。
/// @MainActor 隔离，因为 ModelContext 访问需在主线程。
@MainActor
final class SwiftDataMessageRepository: MessageRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchMessages(conversationId: UUID) async throws -> [ChatMessageDTO] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversation?.id == conversationId },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor).map { $0.toDTO() }
    }

    func save(_ message: ChatMessageDTO) async throws {
        // 查找现有消息
        let messageId = message.id
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.id == messageId }
        )
        if let existing = try context.fetch(descriptor).first {
            // 更新现有消息
            existing.content = message.content
            existing.role = message.role
            existing.toolCallId = message.toolCallId
            existing.toolName = message.toolName
            existing.injectionChecked = message.injectionChecked
            // imageData/attachedImage 从 base64 解码
            if let base64 = message.imageData {
                existing.imageData = Data(base64Encoded: base64)
            }
            if let base64 = message.attachedImage {
                existing.attachedImage = Data(base64Encoded: base64)
            }
            // toolCalls 编码为 JSON
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                do {
                    existing.toolCallData = try JSONEncoder().encode(toolCalls)
                } catch {
                    // toolCalls 编码失败：toolCallData 留空，LLM 多轮调用上下文丢失
                    // 记录日志便于排查（ToolCallDTO 应保证 Codable 不失败）
                    Logger.storage.error("更新消息时 toolCalls 编码失败 (messageId=\(message.id, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            // 创建新消息
            let toolCallData: Data?
            if let toolCalls = message.toolCalls {
                do {
                    toolCallData = try JSONEncoder().encode(toolCalls)
                } catch {
                    Logger.storage.error("创建消息时 toolCalls 编码失败 (messageId=\(message.id, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                    toolCallData = nil
                }
            } else {
                toolCallData = nil
            }
            let newMessage = ChatMessage(
                role: message.role,
                content: message.content,
                imageData: message.imageData.flatMap { Data(base64Encoded: $0) },
                attachedImage: message.attachedImage.flatMap { Data(base64Encoded: $0) },
                toolCallData: toolCallData,
                toolCallId: message.toolCallId,
                toolName: message.toolName
            )
            newMessage.id = message.id
            newMessage.timestamp = message.createdAt
            newMessage.injectionChecked = message.injectionChecked
            // 关联到会话
            let convDescriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate { $0.id == message.conversationId }
            )
            if let conversation = try context.fetch(convDescriptor).first {
                newMessage.conversation = conversation
                conversation.messages.append(newMessage)
            }
            context.insert(newMessage)
        }
        try context.save()
    }

    func delete(conversationId: UUID) async throws {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversation?.id == conversationId }
        )
        for message in try context.fetch(descriptor) {
            context.delete(message)
        }
        try context.save()
    }

    func delete(messageId: UUID) async throws {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.id == messageId }
        )
        for message in try context.fetch(descriptor) {
            context.delete(message)
        }
        try context.save()
    }

    func submitFeedback(messageId: UUID, isPositive: Bool?, citations _: [String]?) async throws {
        // 注意：MessageFeedback 当前模型不存储 citations，仅存储 isPositive。
        // citations 参数保留在协议中以备未来扩展，此处忽略。
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.id == messageId }
        )
        guard let message = try context.fetch(descriptor).first else { return }
        _ = message  // 确保消息存在
        // 查找或创建 MessageFeedback
        let feedbackDescriptor = FetchDescriptor<MessageFeedback>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        if let existing = try context.fetch(feedbackDescriptor).first {
            existing.isPositive = isPositive ?? false
        } else {
            let feedback = MessageFeedback(
                messageId: messageId,
                isPositive: isPositive ?? false
            )
            context.insert(feedback)
        }
        try context.save()
    }
}

// MARK: - ChatMessage -> DTO 转换扩展

extension ChatMessage {
    /// 将 SwiftData @Model ChatMessage 转为平台无关 ChatMessageDTO
    func toDTO() -> ChatMessageDTO {
        let conversationId = conversation?.id ?? UUID()
        // toolCallData 解码
        var toolCalls: [ToolCallDTO]? = nil
        if let data = toolCallData,
           let decoded = try? JSONDecoder().decode([ToolCallDTO].self, from: data) {
            toolCalls = decoded
        }
        return ChatMessageDTO(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            toolCalls: toolCalls,
            toolCallId: toolCallId,
            toolName: toolName,
            imageData: imageData?.base64EncodedString(),
            attachedImage: attachedImage?.base64EncodedString(),
            injectionChecked: injectionChecked,
            createdAt: timestamp
        )
    }
}

// MARK: - ToolCallDTO Codable（用于 JSON 编解码）

extension ToolCallDTO {
    // 已遵循 Codable，但需确保 arguments 字段编码正确
    // 默认实现已满足需求
}
