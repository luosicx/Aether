import AetherServices
import Foundation
import SwiftData

/// 会话与消息持久化服务，封装 SwiftData ModelContext 操作。@MainActor 隔离。
/// Task 1.7: 通过注入 ConversationIndexer 协议解耦对 SpotlightIndexer 的直接依赖。
@MainActor
final class ChatStorage {
    /// SwiftData 上下文
    let modelContext: ModelContext
    /// 会话索引器（平台无关协议）。nil 时不索引；默认 SpotlightIndexer.shared（向后兼容）。
    private let indexer: ConversationIndexer?

    /// 注入 ModelContext 与可选 indexer
    init(modelContext: ModelContext, indexer: ConversationIndexer? = SpotlightIndexer.shared) {
        self.modelContext = modelContext
        self.indexer = indexer
    }

    // MARK: - 私有 helper

    /// 统一执行 modelContext.save()，避免 `try?` 静默吞掉持久化错误。
    /// 触发场景：磁盘已满、模型校验失败、并发上下文冲突等。
    /// 生产环境打印日志，Debug 环境通过 assertionFailure 暴露问题。
    private func save(_ context: String) {
        do {
            try modelContext.save()
        } catch {
            print("ChatStorage save failed (\(context)): \(error)")
            assertionFailure("ChatStorage save failed (\(context)): \(error)")
        }
    }

    /// 将 Conversation 转换为 ConversationIndexDTO 并通过 indexer 协议异步索引。
    /// indexer 为 nil 时直接返回（不索引）。Task 解耦避免阻塞 @MainActor。
    private func indexConversation(_ conversation: Conversation) {
        guard let indexer else { return }
        let dto = ConversationIndexDTO(
            id: conversation.id,
            title: conversation.title,
            lastMessageContent: conversation.messages.last?.content,
            createdAt: conversation.createdAt
        )
        Task { await indexer.index(conversation: dto) }
    }

    /// 创建会话并插入 modelContext。不立即 save（首次 save 触发 schema migration check 阻塞 200-500ms），
    /// save 延迟到首次发消息时。默认 title="新对话"，systemPrompt="你是一个有帮助的AI助手。"
    func createConversation(title: String = "新对话", systemPrompt: String = "你是一个有帮助的AI助手。") -> Conversation {
        let conversation = Conversation(title: title, systemPrompt: systemPrompt)
        modelContext.insert(conversation)
        // 不立即 save（首次 save 触发 schema migration check，阻塞 200-500ms）
        // save 延迟到首次发消息时（ChatViewModel.sendMessage 中会 save）
        // Day 18: 同步 Spotlight 索引（新会话虽为空，仍索引标题便于检索）
        indexConversation(conversation)
        return conversation
    }

    /// 删除会话并立即 save
    func deleteConversation(_ conversation: Conversation) {
        let conversationId = conversation.id
        modelContext.delete(conversation)
        save("deleteConversation")
        // Day 18: 从 Spotlight 索引中移除该会话
        Task { await indexer?.remove(conversationId: conversationId) }
    }

    /// 重命名并 save
    func renameConversation(_ conversation: Conversation, to newTitle: String) {
        conversation.title = newTitle
        save("renameConversation")
        // Day 18: 标题变更后重新索引 Spotlight
        indexConversation(conversation)
    }

    /// 翻转 isPinned 并 save
    /// Day 9: 翻转会话置顶状态并保存
    func togglePin(_ conversation: Conversation) {
        conversation.isPinned.toggle()
        save("togglePin")
    }

    /// Day 23: 拖拽排序后更新 order 字段并持久化。
    /// 按传入的列表顺序依次赋值 order = 0, 1, 2…，保证排序稳定。
    func reorder(_ conversations: [Conversation]) {
        for (index, conv) in conversations.enumerated() {
            conv.order = index
        }
        save("reorder")
    }

    /// Task 21: 从父对话的指定消息处分叉创建新对话。
    /// 新对话的 parentConversationID 设为父对话 ID，parentMessageID 设为分叉点消息 ID。
    /// 复制父对话中从开头到分叉点（含）的所有消息到新对话。
    /// - Parameters:
    ///   - parent: 父对话（分叉来源）
    ///   - messageID: 分叉点消息 ID
    /// - Returns: 新创建的分叉对话
    /// - Throws: ForkError.messageNotFound 如果分叉点消息不存在于父对话中
    func forkConversation(from parent: Conversation, at messageID: UUID) throws -> Conversation {
        // 查找分叉点消息在父对话消息列表中的位置
        guard let forkIndex = parent.messages.firstIndex(where: { $0.id == messageID }) else {
            throw ForkError.messageNotFound
        }

        // 创建新对话，继承父对话的标题与系统提示词
        let forkedTitle = "\(parent.title)（分叉）"
        let forkedConversation = Conversation(title: forkedTitle, systemPrompt: parent.systemPrompt)
        forkedConversation.parentConversationID = parent.id
        forkedConversation.parentMessageID = messageID
        modelContext.insert(forkedConversation)

        // 复制从开头到分叉点（含）的所有消息到新对话
        // 使用 0...forkIndex 确保包含分叉点消息本身
        for originalMessage in parent.messages[0...forkIndex] {
            let copiedMessage = ChatMessage(
                role: originalMessage.role,
                content: originalMessage.content,
                imageData: originalMessage.imageData,
                attachedImage: originalMessage.attachedImage,
                toolCallData: originalMessage.toolCallData,
                toolCallId: originalMessage.toolCallId,
                toolName: originalMessage.toolName
            )
            copiedMessage.conversation = forkedConversation
            forkedConversation.messages.append(copiedMessage)
        }

        save("forkConversation")
        // Day 18: 同步 Spotlight 索引
        indexConversation(forkedConversation)
        return forkedConversation
    }

    /// Task 21: 获取指定对话的所有直接子对话（分叉版本）
    /// - Parameter conversationID: 父对话 ID
    /// - Returns: 子对话列表，按 createdAt 升序排列
    func fetchChildConversations(of conversationID: UUID) -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        return all.filter { $0.parentConversationID == conversationID }
    }

    /// 添加消息，关联 conversation，save
    func addMessage(to conversation: Conversation, role: String, content: String, imageData: Data? = nil) -> ChatMessage {
        let message = ChatMessage(role: role, content: content, imageData: imageData)
        message.conversation = conversation
        conversation.messages.append(message)
        save("addMessage")
        // Day 18: 消息更新后重新索引 Spotlight（contentDescription 取最后一条消息）
        indexConversation(conversation)
        return message
    }

    /// 获取所有会话。为何内存排序：SwiftData SortDescriptor 不直接支持 Bool 排序（需 NSObject），
    /// 先按 createdAt 降序 fetch，再在内存按 isPinned 降序排（置顶在前）。
    /// Day 9: 排序规则——先按 isPinned 降序，再按 createdAt 降序
    /// Day 23: 排序规则——先按 isPinned 降序，再按 order 升序，再按 createdAt 降序
    /// （order 默认 0，未手动排序时退化为 createdAt 降序，保持向后兼容）
    func fetchConversations() -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let raw = (try? modelContext.fetch(descriptor)) ?? []
        // SwiftData 的 SortDescriptor 不直接支持 Bool 排序（需 NSObject），
        // 在内存中按 isPinned 降序排（置顶在前），同组内按 order 升序，再按 createdAt 降序
        return raw.sorted { a, b in
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }
            if a.order != b.order {
                return a.order < b.order
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
            Task { await indexer?.remove(conversationId: convId) }
        }
        save("cleanupEmptyConversations")
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
        let preferenceDescriptor = FetchDescriptor<UserPreference>()

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
        if let prefs = try? modelContext.fetch(preferenceDescriptor) {
            for pref in prefs { modelContext.delete(pref) }
        }
        save("wipeAllData")
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
        save("fetchPreference")
        return preference
    }

    /// 更新或创建偏好：复用 fetchPreference 获取记录后写入新值
    func savePreference(tone: String, tools: [String], fact: String) {
        let preference = fetchPreference()
        preference.preferredTone = tone
        preference.preferredTools = tools
        preference.customFact = fact
        save("savePreference")
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
        save("saveFeedback")
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
        save("updateFeedback")
    }
}

/// Task 21: 分叉操作错误类型
enum ForkError: Error {
    /// 分叉点消息在父对话中不存在
    case messageNotFound
}
