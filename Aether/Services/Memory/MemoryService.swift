import Foundation
import SwiftData
import AetherServices

/// 记忆管理服务，封装 Memory 的存储、语义检索（基于 embedding 相似度）与关键词搜索。@MainActor 隔离。
///
/// 设计要点：
/// - remember：生成 embedding 后存入 SwiftData；若无可用 API Key 或 embedding 失败，仍存储记忆（embedding 留空），保证内容不丢失。
/// - recall：语义检索，对查询生成 embedding 后与所有记忆计算余弦相似度，取相似度最高的前 `limit` 条。
/// - search：关键词搜索，按 content 本地大小写不敏感匹配。
@MainActor
final class MemoryService {
    /// SwiftData 上下文
    private let modelContext: ModelContext
    /// 嵌入服务（可注入，默认使用 QwenClient 作为 provider；测试可注入 stub）
    private let embeddingService: EmbeddingService

    /// 创建 MemoryService 实例
    /// - Parameters:
    ///   - modelContext: SwiftData 上下文
    ///   - embeddingService: 嵌入服务，nil 时使用 Qwen 作为默认 embedding provider
    init(modelContext: ModelContext, embeddingService: EmbeddingService? = nil) {
        self.modelContext = modelContext
        if let service = embeddingService {
            self.embeddingService = service
        } else {
            // 使用 Qwen 作为 embedding provider（DeepSeek 不支持 embedding 端点）
            // resolveEmbeddingAPIKey() 返回 Qwen Key，需匹配 client 才能正确生成 embedding
            self.embeddingService = EmbeddingService(client: QwenClient())
        }
    }

    // MARK: - 存储记忆

    /// 存储记忆。生成 embedding 后插入 modelContext 并 save。
    /// 若无可用 API Key 或 embedding 生成失败，仍存储记忆（embedding 留空），保证内容不丢失。
    /// - Parameters:
    ///   - content: 记忆内容
    ///   - category: 类别，默认 "context"
    ///   - importance: 重要程度 0.0 - 1.0，默认 0.5
    ///   - sourceConversationID: 来源对话 ID，默认 nil
    /// - Returns: 已持久化的 Memory 实例
    @discardableResult
    func remember(content: String, category: String = "context", importance: Double = 0.5, sourceConversationID: UUID? = nil) async throws -> Memory {
        // 尝试生成 embedding；失败时静默降级为空 embedding（内容仍需保存）
        var embedding: [Double] = []
        if let apiKey = resolveEmbeddingAPIKey(), !apiKey.isEmpty {
            if let emb = try? await generateEmbedding(for: content, apiKey: apiKey) {
                embedding = emb
            }
        }
        let memory = Memory(
            content: content,
            embedding: embedding,
            category: category,
            importance: importance,
            sourceConversationID: sourceConversationID
        )
        modelContext.insert(memory)
        try modelContext.save()
        return memory
    }

    // MARK: - 语义检索

    /// 基于语义相似度检索记忆。对查询生成 embedding，与所有记忆计算余弦相似度，取相似度最高的前 `limit` 条。
    /// 若无可用 API Key 或 embedding 生成失败，返回空数组（语义检索无法进行）。
    /// - Parameters:
    ///   - query: 查询文本
    ///   - limit: 返回条数上限，默认 5
    /// - Returns: 按相似度降序排列的记忆数组
    func recall(query: String, limit: Int = 5) async throws -> [Memory] {
        guard let apiKey = resolveEmbeddingAPIKey(), !apiKey.isEmpty else { return [] }
        guard let queryEmbedding = try? await generateEmbedding(for: query, apiKey: apiKey),
              !queryEmbedding.isEmpty else { return [] }

        let descriptor = FetchDescriptor<Memory>()
        let all = try modelContext.fetch(descriptor)
        // 仅对有 embedding 的记忆计算相似度，按相似度降序取前 limit
        let scored = all.compactMap { memory -> (Memory, Double)? in
            guard !memory.embedding.isEmpty else { return nil }
            let score = cosineSimilarity(queryEmbedding, memory.embedding)
            return (memory, score)
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - 关键词搜索

    /// 按关键词搜索记忆（content 本地大小写不敏感匹配）。
    /// - Parameters:
    ///   - keyword: 关键词
    ///   - limit: 返回条数上限，默认 10
    /// - Returns: 匹配的记忆数组，按创建时间降序
    func search(keyword: String, limit: Int = 10) throws -> [Memory] {
        let descriptor = FetchDescriptor<Memory>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        return all
            .filter { $0.content.localizedCaseInsensitiveContains(keyword) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 删除

    /// 删除指定记忆并 save。
    /// - Parameter memory: 待删除的 Memory 实例
    func delete(memory: Memory) throws {
        modelContext.delete(memory)
        try modelContext.save()
    }

    // MARK: - 查询

    /// 获取所有记忆，按创建时间降序。
    /// - Returns: 全部 Memory 数组
    func getAllMemories() throws -> [Memory] {
        let descriptor = FetchDescriptor<Memory>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// 按类别获取记忆，按创建时间降序。
    /// - Parameter category: 类别 "preference" / "fact" / "instruction" / "context"
    /// - Returns: 匹配类别的 Memory 数组
    func getByCategory(_ category: String) throws -> [Memory] {
        let descriptor = FetchDescriptor<Memory>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        return all.filter { $0.category == category }
    }

    // MARK: - 相似度计算

    /// 计算两个向量的余弦相似度。长度不等或空向量返回 0；零范数返回 0。
    /// - Parameters:
    ///   - a: 向量 A
    ///   - b: 向量 B
    /// - Returns: 余弦相似度，范围 -1.0 ~ 1.0
    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (sqrt(normA) * sqrt(normB))
    }

    // MARK: - 私有 helper

    /// 解析可用于 embedding 的 API Key。
    /// 优先使用 Qwen（DeepSeek API 不提供 embeddings 端点）；若无 Qwen Key 返回 nil。
    /// - Returns: API Key 字符串，无可用 Key 时返回 nil
    private func resolveEmbeddingAPIKey() -> String? {
        KeychainManager.shared.getAPIKey(for: .qwen)
    }

    /// 调用 EmbeddingService 对单条文本生成 embedding，并将 [Float] 转为 [Double] 存储。
    /// - Parameters:
    ///   - text: 待嵌入文本
    ///   - apiKey: Embedding API Key
    /// - Returns: Double 形式的 embedding 向量
    private func generateEmbedding(for text: String, apiKey: String) async throws -> [Double] {
        let embeddings = try await embeddingService.embed(texts: [text], apiKey: apiKey)
        guard let emb = embeddings.first, !emb.isEmpty else { return [] }
        return emb.map { Double($0) }
    }
}
