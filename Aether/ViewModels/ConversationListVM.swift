import Foundation
import SwiftData

/// 会话列表 ViewModel，管理会话 CRUD 与置顶。使用 @Observable + @MainActor 隔离。
@Observable
@MainActor
final class ConversationListVM {
    /// 会话列表
    var conversations: [Conversation] = []
    /// ChatStorage 实例（lazy 初始化）
    private var storage: ChatStorage?

    /// 加载会话列表，初始化 storage，默认先清理空对话再 fetch
    /// - Parameter cleanupEmpty: 是否清理无消息的空对话，默认 true（生产场景 ChatView.onAppear 需要）
    func load(modelContext: ModelContext, cleanupEmpty: Bool = true) {
        storage = ChatStorage(modelContext: modelContext)
        if cleanupEmpty {
            // 清理无消息的空对话，避免堆积
            storage?.cleanupEmptyConversations()
        }
        conversations = storage?.fetchConversations() ?? []
    }

    /// 创建会话并插入列表头部。默认 title="新对话"，systemPrompt=SettingsViewModel.defaultSystemPrompt
    func createConversation(title: String = "新对话", systemPrompt: String = SettingsViewModel.defaultSystemPrompt) -> Conversation? {
        let conv = storage?.createConversation(title: title, systemPrompt: systemPrompt)
        if let conv = conv {
            conversations.insert(conv, at: 0)
        }
        return conv
    }

    /// 删除会话，同步从列表移除
    func deleteConversation(_ conversation: Conversation) {
        storage?.deleteConversation(conversation)
        conversations.removeAll { $0.id == conversation.id }
    }

    /// 批量删除会话
    func deleteConversations(_ conversationsToDelete: [Conversation]) {
        let ids = Set(conversationsToDelete.map { $0.id })
        for conv in conversationsToDelete {
            storage?.deleteConversation(conv)
        }
        conversations.removeAll { ids.contains($0.id) }
    }

    /// 重命名会话
    func renameConversation(_ conversation: Conversation, to title: String) {
        storage?.renameConversation(conversation, to: title)
    }

    /// Day 9: 翻转置顶状态并重新加载列表（保证排序正确）
    func togglePin(_ conversation: Conversation) {
        storage?.togglePin(conversation)
        if let storage = storage {
            conversations = storage.fetchConversations()
        }
    }

    /// Day 23: 拖拽排序。移动 conversations 数组元素并更新 order 字段持久化。
    /// - Parameters:
    ///   - source: 被移动的元素索引集合
    ///   - destination: 目标偏移量（与 Array.move(fromOffsets:toOffset:) 语义一致）
    func reorder(from source: IndexSet, to destination: Int) {
        conversations.move(fromOffsets: source, toOffset: destination)
        storage?.reorder(conversations)
    }

    /// 若会话标题仍为"新对话"且有用户消息，用首条用户消息前 20 字作为新标题
    /// （不足 20 字不加「…」）
    func autoTitleIfNeeded(for conversation: Conversation) {
        guard conversation.title == "新对话",
              let firstUserMsg = conversation.messages.first(where: { $0.role == "user" }),
              !firstUserMsg.content.isEmpty else { return }
        let prefix = String(firstUserMsg.content.prefix(20))
        let newTitle = prefix.count < firstUserMsg.content.count ? "\(prefix)…" : prefix
        renameConversation(conversation, to: newTitle)
    }
}
