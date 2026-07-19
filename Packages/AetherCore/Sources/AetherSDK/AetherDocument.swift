import Foundation

/// Task 24: Aether SDK RAG 检索结果文档。
///
/// `AetherClient.retrieve(query:topK:)` 返回的文档分块。
/// 与 App 层 SwiftData `DocumentChunk` 解耦，由 App 层桥接填充。
public struct AetherDocument: Sendable, Equatable {
    /// 文档分块内容
    public let content: String
    /// 来源标识（文件名 / URL / 知识库 ID 等）
    public let source: String
    /// 相似度分数 [0, 1]
    public let score: Double
    /// 元数据（可选，如页码、章节、chunk index 等）
    public let metadata: [String: String]

    public init(content: String, source: String, score: Double, metadata: [String: String] = [:]) {
        self.content = content
        self.source = source
        self.score = score
        self.metadata = metadata
    }
}

/// Task 24: RAG 检索 Provider 协议。
///
/// App 层的 `RAGService` 通过适配器实现此协议即可接入 SDK。
/// SDK 不直接依赖 SwiftData（保持 SPM 包可独立分发）。
public protocol AetherRAGProvider: Sendable {
    /// 检索 topK 相关文档
    /// - Parameters:
    ///   - query: 用户查询
    ///   - topK: 返回数量
    ///   - knowledgeBaseID: 知识库 ID
    /// - Returns: 相关文档列表
    func retrieve(query: String, topK: Int, knowledgeBaseID: String) async throws -> [AetherDocument]
}

/// Task 24: Embedding Provider 协议。
///
/// App 层的 `EmbeddingService` 通过适配器实现此协议即可接入 SDK。
/// 默认实现复用 `LLMProvider.embed`。
public protocol AetherEmbeddingProvider: Sendable {
    /// 批量文本嵌入
    /// - Parameters:
    ///   - texts: 文本数组
    ///   - apiKey: API Key
    /// - Returns: 向量数组（按 index 排序）
    func embed(texts: [String], apiKey: String) async throws -> [[Float]]
}
