import Foundation
import AetherFoundation
import AetherRust

/// 语义缓存，基于 embedding 余弦相似度匹配历史 query。命中时直接返回缓存的 response，跳过 LLM 请求。
/// @MainActor 隔离保证线程安全。
///
/// cosine 计算已迁移至 Rust（aether-core），本类仅做转发。
/// 如需回退到纯 Swift 实现，将 `useRust` 置为 false 即可。
@MainActor
public final class SemanticCache {
    /// 切换开关：true 走 Rust 核心，false 走下方纯 Swift 兜底实现。
    private static let useRust = true
    /// 缓存数组，每项含 query / embedding / response
    private var cache: [(query: String, embedding: [Float], response: String)] = []
    /// 最大容量 100，超出时移除最早项（FIFO 驱逐）
    private let maxCapacity = 100
    /// 相似度阈值 0.92，严格大于才命中（=不命中）
    private let similarityThreshold: Float = 0.92

    /// 公开初始化器，允许 App target 创建实例
    public init() {}

    /// 查询缓存。入参 query 仅用于调试，实际匹配用 embedding。返回命中的 response 或 nil。
    public func get(query: String, embedding: [Float]) -> String? {
        for entry in cache where cosineSimilarity(embedding, entry.embedding) > similarityThreshold {
            return entry.response
        }
        return nil
    }

    /// 写入缓存。容量满时移除最早项。
    public func set(query: String, embedding: [Float], response: String) {
        if cache.count >= maxCapacity {
            cache.removeFirst()
        }
        cache.append((query: query, embedding: embedding, response: response))
    }

    /// 计算两个向量的余弦相似度。长度不等或空向量返回 0。零范数向量（全零）返回 0 避免除零。
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        if Self.useRust {
            return AetherRustVector.cosine(a, b)
        }
        return cosineSimilaritySwift(a, b)
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    private func cosineSimilaritySwift(_ a: [Float], _ b: [Float]) -> Float {
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
        return dot / (sqrt(normA) * sqrt(normB))
    }
}
