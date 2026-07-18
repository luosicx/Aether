import Foundation

/// Task 19 阶段 1: 纯 Swift 暴力扫描向量存储（sqlite-vec 降级方案）。
///
/// 设计要点：
/// - 内存中维护 [(id, embedding, metadata)] 数组，O(N×D) 暴力扫描余弦相似度。
/// - 性能不及 sqlite-vec ANN，但作为降级方案保证 CI 与沙箱环境功能可用。
/// - actor 串行化保证线程安全。
/// - 调用方通过 `VectorStoreFactory.shared.store()` 自动选择是否降级。
actor BruteForceVectorStore: VectorStore {
    /// 恒为 true（降级方案始终可用）
    let isAvailable: Bool = true

    /// 内存中的记录数组
    private var records: [(id: UUID, embedding: [Double], metadata: [String: String])] = []

    /// 创建 BruteForceVectorStore 实例
    /// 注：纯内存降级方案无需初始化资源；显式声明 init() 以便测试与 VectorStoreFactory 构造。
    init() {}

    func initialize() async throws {
        // 无需初始化，纯内存
    }

    func upsert(id: UUID, embedding: [Double], metadata: [String: String]) async throws {
        records.removeAll { $0.id == id }
        records.append((id: id, embedding: embedding, metadata: metadata))
    }

    func upsertBatch(_ records: [(id: UUID, embedding: [Double], metadata: [String: String])]) async throws {
        for record in records {
            self.records.removeAll { $0.id == record.id }
            self.records.append(record)
        }
    }

    func query(_ query: [Double], limit: Int) async throws -> [VectorSearchResult] {
        guard !query.isEmpty else { return [] }
        var scored: [VectorSearchResult] = []
        for record in records {
            let sim = Self.cosineSimilarity(query, record.embedding)
            scored.append(VectorSearchResult(id: record.id, similarity: sim, metadata: record.metadata))
        }
        return scored.sorted { $0.similarity > $1.similarity }.prefix(limit).map { $0 }
    }

    func delete(id: UUID) async throws {
        records.removeAll { $0.id == id }
    }

    func deleteAll() async throws {
        records.removeAll()
    }

    func count() async throws -> Int {
        records.count
    }

    // MARK: - 静态相似度计算（供 RecallEngine 等共享）

    /// 计算两个向量的余弦相似度。长度不等或空向量返回 0；零范数返回 0。
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
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
        return dot / (Foundation.sqrt(normA) * Foundation.sqrt(normB))
    }
}
