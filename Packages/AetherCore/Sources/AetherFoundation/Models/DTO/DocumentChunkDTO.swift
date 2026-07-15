import Foundation

/// 平台无关的文档分块 DTO（用于 RAG 知识库）
///
/// embedding 为 Float 数组，与底层 SwiftData @Model 一致。
/// metadata 存储分块的元信息（如页码、标题），跨平台兼容。
public struct DocumentChunkDTO: Sendable, Codable, Identifiable {
    public let id: UUID
    public var documentId: UUID?
    public var content: String
    public var embedding: [Float]
    public var source: String
    public var chunkIndex: Int
    public var weight: Float
    public var createdAt: Date

    public init(
        id: UUID,
        documentId: UUID? = nil,
        content: String,
        embedding: [Float] = [],
        source: String = "",
        chunkIndex: Int = 0,
        weight: Float = 1.0,
        createdAt: Date
    ) {
        self.id = id
        self.documentId = documentId
        self.content = content
        self.embedding = embedding
        self.source = source
        self.chunkIndex = chunkIndex
        self.weight = weight
        self.createdAt = createdAt
    }
}

/// 平台无关的文档元数据 DTO
///
/// 用于 RAG 上传时关联分块与其所属文档。
public struct DocumentDTO: Sendable, Codable, Identifiable {
    public let id: UUID
    public var userId: UUID
    public var title: String
    public var source: String
    public var createdAt: Date

    public init(id: UUID, userId: UUID, title: String, source: String, createdAt: Date) {
        self.id = id
        self.userId = userId
        self.title = title
        self.source = source
        self.createdAt = createdAt
    }
}
