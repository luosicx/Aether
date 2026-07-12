import Foundation
import SwiftData

/// 持久化记忆条目，供 MemoryService 做语义检索（基于 embedding 相似度）与关键词搜索。
/// category 取值："preference" / "fact" / "instruction" / "context"。
@Model
final class Memory {
    /// 记忆唯一标识
    var id: UUID
    /// 记忆内容
    var content: String
    /// embedding 向量（由 EmbeddingService 生成，Float 转 Double 存储；未生成时为空数组）
    var embedding: [Double]
    /// 创建时间
    var createdAt: Date
    /// 类别："preference" / "fact" / "instruction" / "context"
    var category: String
    /// 重要程度 0.0 - 1.0，可用于检索结果加权
    var importance: Double
    /// 来源对话 ID（可选，追溯记忆来自哪个会话）
    var sourceConversationID: UUID?

    /// 创建 Memory 实例
    /// - Parameters:
    ///   - content: 记忆内容
    ///   - embedding: embedding 向量，默认空数组（调用方可在生成后回填）
    ///   - category: 类别，默认 "context"
    ///   - importance: 重要程度，默认 0.5
    ///   - sourceConversationID: 来源对话 ID，默认 nil
    init(content: String, embedding: [Double] = [], category: String = "context", importance: Double = 0.5, sourceConversationID: UUID? = nil) {
        self.id = UUID()
        self.content = content
        self.embedding = embedding
        self.createdAt = Date()
        self.category = category
        self.importance = importance
        self.sourceConversationID = sourceConversationID
    }
}
