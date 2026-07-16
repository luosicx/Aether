import Foundation
import SwiftData
import AetherServices

/// RAG 检索增强生成服务，负责文档索引、相似度检索、上下文增强。@MainActor 隔离。
///
/// cosine 计算已迁移至 Rust（aether-core，AetherRustVector），统一 SemanticCache/MemoryService 三端实现。
/// `retrieve` 与 `buildAugmentedContext` 共享同一 `scoredChunks` 私有方法，消除原双重暴力扫描。
@MainActor
final class RAGService {
    /// 文档分块器
    private let chunker = DocumentChunker()
    /// 嵌入服务（可注入，默认 EmbeddingService()）
    private let embeddingService: EmbeddingService
    /// 切换开关：true 走 Rust 核心，false 走下方纯 Swift 兜底实现。
    private static let useRust = true

    /// 注入嵌入服务，默认 EmbeddingService()
    init(embeddingService: EmbeddingService = EmbeddingService()) {
        self.embeddingService = embeddingService
    }

    /// 索引文档。流程：1) 删除同 source 的旧 chunks（去重）；2) chunkDocument 切分；
    /// 3) 空 chunks 提前返回；4) embedBatch 批量嵌入；5) 插入 modelContext 并 save。
    func indexDocument(text: String, source: String, modelContext: ModelContext, apiKey: String) async throws {
        // 去重：先删除相同 source 的旧 chunks
        let existingDescriptor = FetchDescriptor<DocumentChunk>(
            predicate: #Predicate { $0.source == source }
        )
        let existing = try modelContext.fetch(existingDescriptor)
        for chunk in existing {
            modelContext.delete(chunk)
        }

        let chunks = chunker.chunkDocument(text, source: source)
        guard !chunks.isEmpty else { return }
        let texts = chunks.map(\.content)
        let embeddings = try await embeddingService.embedBatch(texts, apiKey: apiKey)
        for (index, chunk) in chunks.enumerated() {
            if index < embeddings.count {
                chunk.embedding = embeddings[index]
            }
            modelContext.insert(chunk)
        }
        try modelContext.save()
    }

    /// 检索 topK 最相关分块。流程：1) embed query；2) 空 embedding 返回空；
    /// 3) fetch 全部分块；4) 计算 cosine 相似度；5) 降序排序取前 topK。
    /// Day 12: 最终得分 = cosine 相似度 * chunk.weight，反馈闭环（踩 *=0.8 / 赞 /=0.8）会调整权重。
    func retrieve(query: String, topK: Int = 5, modelContext: ModelContext, apiKey: String) async throws -> [DocumentChunk] {
        let queryEmbeddings = try await embeddingService.embed(texts: [query], apiKey: apiKey)
        guard let queryEmbedding = queryEmbeddings.first, !queryEmbedding.isEmpty else { return [] }
        let descriptor = FetchDescriptor<DocumentChunk>()
        let allChunks = try modelContext.fetch(descriptor)
        // 共享评分逻辑：最终得分 = cosine * weight（默认 1.0；反馈闭环会调整 weight）
        return scoredChunks(queryEmbedding: queryEmbedding, chunks: allChunks, topK: topK, applyWeight: true)
            .map(\.0)
    }

    /// 构建增强上下文。返回三元组：(context, citations, queryEmbedding)。
    /// 流程：1) embed query；2) 空 embedding 返回 ("", [], [])；3) fetch + cosine 排序取前 5；
    /// 4) 无相关块返回 ("", [], embedding)；5) 拼 `[1] [2]` 编号的 prompt。
    /// queryEmbedding 复用语义：返回的 queryEmbedding 供调用方写入语义缓存，避免重复调 embed API。
    func buildAugmentedContext(query: String, modelContext: ModelContext, apiKey: String) async throws -> (context: String, citations: [DocumentChunk], queryEmbedding: [Float]) {
        let queryEmbeddings = try await embeddingService.embed(texts: [query], apiKey: apiKey)
        guard let queryEmbedding = queryEmbeddings.first, !queryEmbedding.isEmpty else {
            return ("", [], [])
        }
        let descriptor = FetchDescriptor<DocumentChunk>()
        let allChunks = try modelContext.fetch(descriptor)
        // buildAugmentedContext 不应用 weight（仅 retrieve 的反馈闭环用 weight）
        let relevantChunks = scoredChunks(queryEmbedding: queryEmbedding, chunks: allChunks, topK: 5, applyWeight: false)
            .map(\.0)
        guard !relevantChunks.isEmpty else { return ("", [], queryEmbedding) }
        let context = relevantChunks
            .enumerated()
            .map { "[\($0.offset + 1)] \($0.element.content)" }
            .joined(separator: "\n\n")
        let prompt = "以下是与问题相关的参考信息：\n\(context)\n\n请基于以上信息回答问题。"
        return (prompt, relevantChunks, queryEmbedding)
    }

    // MARK: - 共享评分逻辑（消除 retrieve / buildAugmentedContext 双重暴力扫描）

    /// 对 chunks 计算 cosine 相似度并按降序取前 topK。
    /// - Parameter applyWeight: true 时最终得分 = cosine * chunk.weight（retrieve 用）；
    ///   false 时仅用 cosine 原始值（buildAugmentedContext 用）。
    private func scoredChunks(queryEmbedding: [Float], chunks: [DocumentChunk], topK: Int, applyWeight: Bool) -> [(DocumentChunk, Double)] {
        chunks
            .map { chunk -> (DocumentChunk, Double) in
                let similarity = cosineSimilarity(queryEmbedding, chunk.embedding)
                let score = applyWeight ? similarity * Double(chunk.weight) : similarity
                return (chunk, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { ($0.0, $0.1) }
    }

    // MARK: - 余弦相似度（转发 Rust）

    /// 计算余弦相似度。长度不等或空向量返回 0。零范数返回 0。
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        if Self.useRust {
            return Double(AetherRustVector.cosine(a, b))
        }
        return cosineSimilaritySwift(a, b)
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    private func cosineSimilaritySwift(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return Double(dot / (sqrt(normA) * sqrt(normB)))
    }
}
