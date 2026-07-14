import Foundation

/// 平台无关的记忆条目 DTO
///
/// category 取值："preference" / "fact" / "instruction" / "context"
/// embedding 为 Double 数组（跨平台统一，即使底层存储为 Float）。
public struct MemoryDTO: Sendable, Codable, Identifiable {
    public let id: UUID
    public var content: String
    public var category: String
    public var importance: Double
    public var embedding: [Double]
    public var sourceConversationId: UUID?
    public var createdAt: Date

    public init(
        id: UUID,
        content: String,
        category: String = "context",
        importance: Double = 0.5,
        embedding: [Double] = [],
        sourceConversationId: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.importance = importance
        self.embedding = embedding
        self.sourceConversationId = sourceConversationId
        self.createdAt = createdAt
    }
}
