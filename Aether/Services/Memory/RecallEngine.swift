import Foundation

/// Task 19 阶段 2: 复合召回引擎。
///
/// 流程：VectorStore ANN top-20 候选 → 复合评分 → top-5 → 同 category 去重（保留最高分）。
///
/// 复合评分公式：
/// ```
/// finalScore = 0.6 × cosineSimilarity + 0.3 × importance + 0.1 × recency
/// ```
/// 时间衰减：半衰期 τ=30 天，`recency = exp(-Δt/τ)`。
/// 用户主动记忆（`isUserExplicit=true`）：`importance=0.8` 固定，且 `recency` 权重不衰减（恒为 1.0）。
actor RecallEngine {
    /// 复合评分权重
    static let weightSimilarity: Double = 0.6
    static let weightImportance: Double = 0.3
    static let weightRecency: Double = 0.1
    /// 时间衰减半衰期（秒）— 30 天
    static let halfLifeSeconds: TimeInterval = 30 * 24 * 60 * 60
    /// ANN 候选数量
    static let candidateLimit: Int = 20
    /// 最终返回数量
    static let defaultResultLimit: Int = 5

    /// 向量存储工厂
    private let vectorStoreFactory: VectorStoreFactory?

    /// 创建 RecallEngine 实例
    /// - Parameter vectorStoreFactory: 向量存储工厂，nil 时使用单例
    init(vectorStoreFactory: VectorStoreFactory? = nil) {
        self.vectorStoreFactory = vectorStoreFactory
    }

    /// 获取 VectorStore
    private var vectorStore: VectorStore {
        get async {
            if let factory = vectorStoreFactory {
                return await factory.store()
            }
            return await VectorStoreFactory.shared.store()
        }
    }

    /// 复合召回：ANN top-K 候选 → 复合评分 → top-5 → 同 category 去重。
    /// - Parameters:
    ///   - query: 查询向量
    ///   - memories: 所有候选 Memory（用于加载元数据与 importance/createdAt）
    ///   - limit: 返回条数上限，默认 5
    ///   - now: 当前时间（默认 Date()），便于测试注入
    /// - Returns: 排序后的 Memory 数组（已更新 lastAccessedAt）
    func recall(query: [Double], memories: [Memory], limit: Int = defaultResultLimit, now: Date = Date()) async -> [Memory] {
        guard !query.isEmpty, !memories.isEmpty else { return [] }
        // 1. 通过 VectorStore ANN 取 top-20 候选
        let candidates = await fetchCandidates(query: query, limit: Self.candidateLimit, memories: memories)
        if candidates.isEmpty {
            // VectorStore 不可用，回退到内存暴力扫描
            return await bruteForceRecall(query: query, memories: memories, limit: limit, now: now)
        }
        // 2. 复合评分
        let scored = candidates.map { (memory, sim) in
            (memory, Self.computeFinalScore(memory: memory, similarity: sim, now: now))
        }
        // 3. 排序 + 同 category 去重（保留最高分）
        let deduped = dedupeByCategory(scored.sorted { $0.1 > $1.1 })
        // 4. 取 top-N
        let topN = Array(deduped.prefix(limit))
        // 5. 更新 lastAccessedAt
        for (memory, _) in topN {
            memory.lastAccessedAt = now
        }
        return topN.map { $0.0 }
    }

    // MARK: - 公开静态评分函数（便于单元测试）

    /// 计算复合评分：`0.6×sim + 0.3×importance + 0.1×recency`。
    /// 用户主动记忆 `recency` 恒为 1.0（不衰减）。
    static func computeFinalScore(memory: Memory, similarity: Double, now: Date) -> Double {
        let importance = memory.importance
        let recency: Double
        if memory.isUserExplicit {
            recency = 1.0
        } else {
            recency = computeRecency(memory: memory, now: now)
        }
        return weightSimilarity * similarity
             + weightImportance * importance
             + weightRecency * recency
    }

    /// 计算时间衰减权重：`recency = exp(-Δt/τ)`，半衰期 τ=30 天。
    /// Δt 基于 `lastAccessedAt`（若存在）或 `createdAt`。
    static func computeRecency(memory: Memory, now: Date) -> Double {
        let reference = memory.lastAccessedAt ?? memory.createdAt
        let delta = now.timeIntervalSince(reference)
        // Δt ≤ 0（未来时间）按 1.0 处理
        if delta <= 0 { return 1.0 }
        return Foundation.exp(-delta / Self.halfLifeSeconds)
    }

    // MARK: - 内部辅助

    /// 通过 VectorStore 取 top-K 候选，返回与 SwiftData Memory 的对齐列表。
    /// 注意：VectorStore 返回的相似度优先；若 VectorStore 不可用则返回空数组（调用方应回退到暴力扫描）。
    private func fetchCandidates(query: [Double], limit: Int, memories: [Memory]) async -> [(Memory, Double)] {
        let store = await vectorStore
        do {
            let results = try await store.query(query, limit: limit)
            if results.isEmpty { return [] }
            let memoryDict = Dictionary(uniqueKeysWithValues: memories.map { ($0.id, $0) })
            return results.compactMap { result in
                guard let memory = memoryDict[result.id] else { return nil }
                return (memory, result.similarity)
            }
        } catch {
            return []
        }
    }

    /// 内存暴力扫描回退路径：计算每条记忆与查询的余弦相似度。
    private func bruteForceRecall(query: [Double], memories: [Memory], limit: Int, now: Date) async -> [Memory] {
        let scored = memories.compactMap { memory -> (Memory, Double)? in
            guard !memory.embedding.isEmpty else { return nil }
            let sim = BruteForceVectorStore.cosineSimilarity(query, memory.embedding)
            let score = Self.computeFinalScore(memory: memory, similarity: sim, now: now)
            return (memory, score)
        }
        let deduped = dedupeByCategory(scored.sorted { $0.1 > $1.1 })
        let topN = Array(deduped.prefix(limit))
        for (memory, _) in topN {
            memory.lastAccessedAt = now
        }
        return topN.map { $0.0 }
    }

    /// 同 category 去重：保留每类别得分最高的记忆。
    private func dedupeByCategory(_ scored: [(Memory, Double)]) -> [(Memory, Double)] {
        var seen: [String: (Memory, Double)] = [:]
        for (memory, score) in scored {
            if let existing = seen[memory.category], existing.1 >= score {
                continue
            }
            seen[memory.category] = (memory, score)
        }
        // 保持原排序顺序
        return scored.filter { item in
            guard let best = seen[item.0.category] else { return false }
            return best.0.id == item.0.id
        }
    }
}
