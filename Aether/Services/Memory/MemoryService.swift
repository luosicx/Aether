import Foundation
import SwiftData
import os
import AetherServices

/// 记忆管理服务，封装 Memory 的存储、语义检索（基于 embedding 相似度）与关键词搜索。@MainActor 隔离。
///
/// 设计要点：
/// - remember：生成 embedding 后存入 SwiftData；若无可用 API Key 或 embedding 失败，仍存储记忆（embedding 留空），保证内容不丢失。
/// - recall：语义检索，对查询生成 embedding 后与所有记忆计算余弦相似度，取相似度最高的前 `limit` 条。
/// - search：关键词搜索，按 content 本地大小写不敏感匹配。
///
/// Task 19 阶段 1 扩展：
/// - `remember` 写入路径双写（SwiftData + VectorStore），VectorStore 不可用时静默降级。
/// - `recall` 切换为 VectorStore ANN 查询（top-K），VectorStore 不可用时回退到 SwiftData 暴力扫描。
@MainActor
final class MemoryService {
    /// SwiftData 上下文
    private let modelContext: ModelContext
    /// 嵌入服务（可注入，默认使用 QwenClient 作为 provider；测试可注入 stub）
    private let embeddingService: EmbeddingService
    /// 向量存储工厂（Task 19 阶段 1；nil 时使用单例）
    private let vectorStoreFactory: VectorStoreFactory?

    /// 创建 MemoryService 实例
    /// - Parameters:
    ///   - modelContext: SwiftData 上下文
    ///   - embeddingService: 嵌入服务，nil 时使用 Qwen 作为默认 embedding provider
    ///   - vectorStoreFactory: 向量存储工厂，nil 时使用 `VectorStoreFactory.shared`
    init(modelContext: ModelContext, embeddingService: EmbeddingService? = nil, vectorStoreFactory: VectorStoreFactory? = nil) {
        self.modelContext = modelContext
        if let service = embeddingService {
            self.embeddingService = service
        } else {
            // 使用 Qwen 作为 embedding provider（DeepSeek 不支持 embedding 端点）
            // resolveEmbeddingAPIKey() 返回 Qwen Key，需匹配 client 才能正确生成 embedding
            self.embeddingService = EmbeddingService(client: QwenClient())
        }
        self.vectorStoreFactory = vectorStoreFactory
    }

    /// Task 19 阶段 1: 获取当前 VectorStore（默认走单例工厂）
    private var vectorStore: VectorStore {
        get async {
            if let factory = vectorStoreFactory {
                return await factory.store()
            }
            return await VectorStoreFactory.shared.store()
        }
    }

    // MARK: - 存储记忆

    /// 存储记忆。生成 embedding 后插入 modelContext 并 save。
    /// 若无可用 API Key 或 embedding 生成失败，仍存储记忆（embedding 留空），保证内容不丢失。
    ///
    /// Task 19 阶段 1: 双写 — 同时写入 SwiftData 与 VectorStore（向量库不可用时静默降级）。
    /// Task 19 阶段 2: 用户主动记忆（`isUserExplicit=true`）默认 importance=0.8 且不随时间衰减。
    /// - Parameters:
    ///   - content: 记忆内容
    ///   - category: 类别，默认 "context"
    ///   - importance: 重要程度 0.0 - 1.0，默认 0.5
    ///   - sourceConversationID: 来源对话 ID，默认 nil
    ///   - isUserExplicit: 是否为用户主动记忆，默认 false（用户主动记忆 importance 强制 0.8 且不衰减）
    /// - Returns: 已持久化的 Memory 实例
    @discardableResult
    func remember(content: String, category: String = "context", importance: Double = 0.5, sourceConversationID: UUID? = nil, isUserExplicit: Bool = false) async throws -> Memory {
        // 尝试生成 embedding；失败时静默降级为空 embedding（内容仍需保存）
        var embedding: [Double] = []
        // S1066: 合并嵌套 if
        if let apiKey = resolveEmbeddingAPIKey(), !apiKey.isEmpty,
           let emb = try? await generateEmbedding(for: content, apiKey: apiKey) {
            embedding = emb
        }
        // Task 19 阶段 2: 用户主动记忆强制 importance=0.8
        let finalImportance = isUserExplicit ? 0.8 : importance
        let memory = Memory(
            content: content,
            embedding: embedding,
            category: category,
            importance: finalImportance,
            sourceConversationID: sourceConversationID,
            isUserExplicit: isUserExplicit
        )
        modelContext.insert(memory)
        try modelContext.save()
        // Task 19 阶段 1: 双写 VectorStore（失败不阻塞主路径）
        if !embedding.isEmpty {
            await writeToVectorStore(memory: memory)
        }
        return memory
    }

    /// Task 19 阶段 1: 将 Memory 写入 VectorStore（双写路径，失败静默降级）。
    private func writeToVectorStore(memory: Memory) async {
        let store = await vectorStore
        let metadata: [String: String] = [
            "category": memory.category,
            "importance": String(memory.importance),
            "createdAt": String(memory.createdAt.timeIntervalSince1970),
            "content": memory.content
        ]
        do {
            try await store.upsert(id: memory.id, embedding: memory.embedding, metadata: metadata)
        } catch {
            // 静默降级：VectorStore 写入失败不影响主流程，但记录日志便于排查
            // 「记忆存在但语义检索召回不到」类问题。SwiftData 主表已写入，用户体验不受影响。
            Logger.memory.error("VectorStore upsert 失败 (memoryId=\(memory.id, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 语义检索

    /// 基于语义相似度检索记忆。对查询生成 embedding，与所有记忆计算余弦相似度，取相似度最高的前 `limit` 条。
    /// 若无可用 API Key 或 embedding 生成失败，返回空数组（语义检索无法进行）。
    ///
    /// Task 19 阶段 1: 优先走 VectorStore ANN 查询；VectorStore 不可用或返回空时回退到 SwiftData 暴力扫描。
    /// - Parameters:
    ///   - query: 查询文本
    ///   - limit: 返回条数上限，默认 5
    /// - Returns: 按相似度降序排列的记忆数组
    func recall(query: String, limit: Int = 5) async throws -> [Memory] {
        guard let apiKey = resolveEmbeddingAPIKey(), !apiKey.isEmpty else { return [] }
        guard let queryEmbedding = try? await generateEmbedding(for: query, apiKey: apiKey),
              !queryEmbedding.isEmpty else { return [] }

        // Task 19 阶段 1: 优先走 VectorStore ANN 查询
        if let results = try? await recallViaVectorStore(queryEmbedding: queryEmbedding, limit: limit),
           !results.isEmpty {
            return results
        }
        // 回退到 SwiftData 暴力扫描
        return try recallViaSwiftData(queryEmbedding: queryEmbedding, limit: limit)
    }

    /// Task 19 阶段 1: 通过 VectorStore 做 ANN 查询，再从 SwiftData 加载完整 Memory 实例。
    private func recallViaVectorStore(queryEmbedding: [Double], limit: Int) async throws -> [Memory]? {
        let store = await vectorStore
        let results = try await store.query(queryEmbedding, limit: limit)
        guard !results.isEmpty else { return [] }
        let ids = results.map { $0.id }
        return try await fetchMemoriesByIDs(ids)
    }

    /// Task 19 阶段 1: SwiftData 暴力扫描回退路径。
    private func recallViaSwiftData(queryEmbedding: [Double], limit: Int) throws -> [Memory] {
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

    /// Task 19 阶段 1: 按 ID 集合批量加载 Memory（保持查询返回的相似度排序）。
    private func fetchMemoriesByIDs(_ ids: [UUID]) async throws -> [Memory] {
        let descriptor = FetchDescriptor<Memory>()
        let all = try modelContext.fetch(descriptor)
        let dict = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { dict[$0] }
    }

    // MARK: - Task 19 阶段 2: 公开 query embedding 生成（供 RecallEngine / SemanticMemoryStore 复用）

    /// 生成查询文本的 embedding 向量。
    /// 内部复用 `embeddingService` 与 `resolveEmbeddingAPIKey()`，失败返回空数组。
    /// - Parameter query: 查询文本
    /// - Returns: embedding 向量；无可用 API Key 或 embedding 失败时返回空数组
    func generateQueryEmbedding(for query: String) async throws -> [Double] {
        guard let apiKey = resolveEmbeddingAPIKey(), !apiKey.isEmpty else { return [] }
        return try await generateEmbedding(for: query, apiKey: apiKey)
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

    /// 删除指定记忆并 save。Task 19 阶段 1: 同步从 VectorStore 移除。
    /// - Parameter memory: 待删除的 Memory 实例
    func delete(memory: Memory) async throws {
        let memoryID = memory.id
        modelContext.delete(memory)
        try modelContext.save()
        // Task 19 阶段 1: 同步移除 VectorStore 中的向量
        let store = await vectorStore
        try? await store.delete(id: memoryID)
    }

    // MARK: - Task 19 阶段 4: 导入支持

    /// 插入导入的记忆（来自 ExportImporter）。
    /// 已包含 id/createdAt 等字段的原始值（不重新生成），用于跨设备恢复。
    /// - Parameter memory: 待插入的 Memory 实例
    func insertImported(_ memory: Memory) throws {
        modelContext.insert(memory)
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

    /// 切换开关：true 走 Rust 核心（AetherRustVector.cosineF64），false 走下方纯 Swift 兜底。
    private static let useRust = true

    /// 计算两个向量的余弦相似度。长度不等或空向量返回 0；零范数返回 0。
    /// - Parameters:
    ///   - a: 向量 A
    ///   - b: 向量 B
    /// - Returns: 余弦相似度，范围 -1.0 ~ 1.0
    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        if Self.useRust {
            return AetherRustVector.cosine(a, b)
        }
        return cosineSimilaritySwift(a, b)
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    private func cosineSimilaritySwift(_ a: [Double], _ b: [Double]) -> Double {
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
