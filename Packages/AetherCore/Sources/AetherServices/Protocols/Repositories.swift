import AetherFoundation
import Foundation

/// 平台无关的会话仓储协议
///
/// 定义会话的增删改查契约，由各平台提供具体实现（如 SwiftDataConversationRepository）。
/// DTO 用 ConversationDTO，隔离底层持久化模型（如 SwiftData @Model）。
public protocol ConversationRepository: Sendable {
    /// 获取所有会话，按 updated_at 降序
    func fetchAll() async throws -> [ConversationDTO]
    /// 按 id 获取单个会话
    func fetch(id: UUID) async throws -> ConversationDTO?
    /// 保存（创建或更新）会话
    func save(_ conversation: ConversationDTO) async throws
    /// 删除指定会话（级联删除其消息）
    func delete(id: UUID) async throws
    /// 按关键词搜索会话标题和最后消息预览
    func search(query: String) async throws -> [ConversationDTO]
    /// 获取子对话（分叉）
    func fetchChildren(parentId: UUID) async throws -> [ConversationDTO]
}

/// 平台无关的消息仓储协议
///
/// 定义聊天消息的持久化与检索契约。
public protocol MessageRepository: Sendable {
    /// 获取指定会话的所有消息，按时间升序
    func fetchMessages(conversationId: UUID) async throws -> [ChatMessageDTO]
    /// 保存单条消息
    func save(_ message: ChatMessageDTO) async throws
    /// 删除指定会话的所有消息
    func delete(conversationId: UUID) async throws
    /// 删除单条消息
    func delete(messageId: UUID) async throws
    /// 提交消息反馈（-1/0/1）
    func submitFeedback(messageId: UUID, isPositive: Bool?, citations: [String]?) async throws
}

/// 平台无关的记忆仓储协议
///
/// 用于跨会话的长期记忆持久化与检索。检索可基于关键词（简化版）
/// 或向量相似度（未来扩展）。
public protocol MemoryRepository: Sendable {
    /// 获取所有记忆，按重要性降序
    func fetchAll() async throws -> [MemoryDTO]
    /// 保存（创建或更新）记忆
    func save(_ memory: MemoryDTO) async throws
    /// 按关键词搜索相关记忆，按重要性降序，限制数量
    func searchRelevant(query: String, limit: Int) async throws -> [MemoryDTO]
    /// 按 id 删除记忆
    func delete(id: UUID) async throws
}

/// 平台无关的文档仓储协议（用于 RAG 知识库）
///
/// 定义文档分块的索引与检索契约。向量检索可由具体实现
/// 决定（简化版用文本匹配，未来扩展为向量相似度）。
public protocol DocumentRepository: Sendable {
    /// 索引文档分块（批量保存）
    func indexDocument(_ chunks: [DocumentChunkDTO]) async throws
    /// 按关键词搜索文档分块，限制数量
    func search(query: String, limit: Int) async throws -> [DocumentChunkDTO]
    /// 调整分块权重（被赞/被踩时）
    func updateWeight(chunkId: UUID, factor: Float) async throws
    /// 删除指定来源的所有分块
    func deleteBySource(_ source: String) async throws
}
