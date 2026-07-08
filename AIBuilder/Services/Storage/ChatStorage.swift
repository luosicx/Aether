import Foundation
import SwiftData

/// 会话与消息持久化服务，封装 SwiftData ModelContext 操作。@MainActor 隔离。
@MainActor
final class ChatStorage {
    /// SwiftData 上下文
    let modelContext: ModelContext

    /// 注入 ModelContext
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 创建会话并插入 modelContext。不立即 save（首次 save 触发 schema migration check 阻塞 200-500ms），
    /// save 延迟到首次发消息时。默认 title="新对话"，systemPrompt="你是一个有帮助的AI助手。"
    func createConversation(title: String = "新对话", systemPrompt: String = "你是一个有帮助的AI助手。") -> Conversation {
        let conversation = Conversation(title: title, systemPrompt: systemPrompt)
        modelContext.insert(conversation)
        // 不立即 save（首次 save 触发 schema migration check，阻塞 200-500ms）
        // save 延迟到首次发消息时（ChatViewModel.sendMessage 中会 save）
        // Day 18: 同步 Spotlight 索引（新会话虽为空，仍索引标题便于检索）
        SpotlightIndexer.index(conversation)
        return conversation
    }

    /// 删除会话并立即 save
    func deleteConversation(_ conversation: Conversation) {
        let conversationId = conversation.id
        modelContext.delete(conversation)
        try? modelContext.save()
        // Day 18: 从 Spotlight 索引中移除该会话
        SpotlightIndexer.removeIndex(conversationId: conversationId)
    }

    /// 重命名并 save
    func renameConversation(_ conversation: Conversation, to newTitle: String) {
        conversation.title = newTitle
        try? modelContext.save()
        // Day 18: 标题变更后重新索引 Spotlight
        SpotlightIndexer.index(conversation)
    }

    /// 翻转 isPinned 并 save
    /// Day 9: 翻转会话置顶状态并保存
    func togglePin(_ conversation: Conversation) {
        conversation.isPinned.toggle()
        try? modelContext.save()
    }

    /// 添加消息，关联 conversation，save
    func addMessage(to conversation: Conversation, role: String, content: String, imageData: Data? = nil) -> ChatMessage {
        let message = ChatMessage(role: role, content: content, imageData: imageData)
        message.conversation = conversation
        conversation.messages.append(message)
        try? modelContext.save()
        // Day 18: 消息更新后重新索引 Spotlight（contentDescription 取最后一条消息）
        SpotlightIndexer.index(conversation)
        return message
    }

    /// 获取所有会话。为何内存排序：SwiftData SortDescriptor 不直接支持 Bool 排序（需 NSObject），
    /// 先按 createdAt 降序 fetch，再在内存按 isPinned 降序排（置顶在前）。
    /// Day 9: 排序规则——先按 isPinned 降序，再按 createdAt 降序
    func fetchConversations() -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let raw = (try? modelContext.fetch(descriptor)) ?? []
        // SwiftData 的 SortDescriptor 不直接支持 Bool 排序（需 NSObject），
        // 在内存中按 isPinned 降序排（置顶在前），同组内已按 createdAt 降序
        return raw.sorted { a, b in
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }
            return a.createdAt > b.createdAt
        }
    }

    /// 清理无消息的空对话（messages 为空），避免会话列表堆积空对话
    func cleanupEmptyConversations() {
        let descriptor = FetchDescriptor<Conversation>()
        guard let allConversations = try? modelContext.fetch(descriptor) else { return }
        for conv in allConversations where conv.messages.isEmpty {
            let convId = conv.id
            modelContext.delete(conv)
            // 同步清理 Spotlight 索引
            SpotlightIndexer.removeIndex(conversationId: convId)
        }
        try? modelContext.save()
    }

    /// 清空所有 SwiftData 数据（仅供 UITEST_RESET_DATA 使用）
    /// 删除所有 Conversation / ChatMessage / DocumentChunk / MessageFeedback / HealthInsight 实体。
    /// 方法幂等：无数据时不报错。
    func wipeAllData() {
        let conversationDescriptor = FetchDescriptor<Conversation>()
        let messageDescriptor = FetchDescriptor<ChatMessage>()
        let chunkDescriptor = FetchDescriptor<DocumentChunk>()
        let feedbackDescriptor = FetchDescriptor<MessageFeedback>()
        let insightDescriptor = FetchDescriptor<HealthInsight>()

        if let conversations = try? modelContext.fetch(conversationDescriptor) {
            for conv in conversations { modelContext.delete(conv) }
        }
        if let messages = try? modelContext.fetch(messageDescriptor) {
            for msg in messages { modelContext.delete(msg) }
        }
        if let chunks = try? modelContext.fetch(chunkDescriptor) {
            for chunk in chunks { modelContext.delete(chunk) }
        }
        if let feedbacks = try? modelContext.fetch(feedbackDescriptor) {
            for fb in feedbacks { modelContext.delete(fb) }
        }
        if let insights = try? modelContext.fetch(insightDescriptor) {
            for insight in insights { modelContext.delete(insight) }
        }
        try? modelContext.save()
    }

    // MARK: - Day 9: 用户偏好读写
    /// 返回当前偏好；若仓库中无偏好记录则创建默认实例并保存后返回
    func fetchPreference() -> UserPreference {
        let descriptor = FetchDescriptor<UserPreference>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        // 无则创建默认实例并保存
        let preference = UserPreference()
        modelContext.insert(preference)
        try? modelContext.save()
        return preference
    }

    /// 更新或创建偏好：复用 fetchPreference 获取记录后写入新值
    func savePreference(tone: String, tools: [String], fact: String) {
        let preference = fetchPreference()
        preference.preferredTone = tone
        preference.preferredTools = tools
        preference.customFact = fact
        try? modelContext.save()
    }

    // MARK: - Day 12: 消息反馈与 RAG 权重闭环
    /// 保存用户反馈。isPositive=false 时对关联 citations chunk weight *= 0.8 降权；
    /// isPositive=true 时对关联 citations chunk weight /= 0.8 提权（上限 1.0）。
    func saveFeedback(messageId: UUID, isPositive: Bool, citations: [DocumentChunk]) {
        let feedback = MessageFeedback(messageId: messageId, isPositive: isPositive)
        modelContext.insert(feedback)
        // 调整关联 chunk 权重
        for chunk in citations {
            if isPositive {
                // 提权：除以 0.8，上限 1.0
                chunk.weight = min(chunk.weight / 0.8, 1.0)
            } else {
                // 降权：乘以 0.8
                chunk.weight *= 0.8
            }
        }
        try? modelContext.save()
    }

    /// 查询某条消息的反馈记录
    func fetchFeedback(messageId: UUID) -> MessageFeedback? {
        let descriptor = FetchDescriptor<MessageFeedback>()
        guard let all = try? modelContext.fetch(descriptor) else { return nil }
        return all.first { $0.messageId == messageId }
    }

    /// 更新反馈状态（切换赞/踩）。撤销旧权重应用新权重。
    func updateFeedback(_ feedback: MessageFeedback, isPositive: Bool, citations: [DocumentChunk]) {
        let oldIsPositive = feedback.isPositive
        feedback.isPositive = isPositive
        // 仅当反馈状态实际变化时调整权重
        if oldIsPositive != isPositive {
            for chunk in citations {
                if isPositive {
                    // 切换为赞：提权（撤销之前降权）
                    chunk.weight = min(chunk.weight / 0.8, 1.0)
                } else {
                    // 切换为踩：降权（撤销之前提权）
                    chunk.weight *= 0.8
                }
            }
        }
        try? modelContext.save()
    }
}
