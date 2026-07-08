import Foundation

/// 嵌入服务，封装 DeepSeekClient 的 embed 能力，提供批量分片聚合
class EmbeddingService {
    /// DeepSeekClient 实例（注意：class 非 final，允许测试子类化注入 stub）
    private let client = DeepSeekClient()

    /// 单次嵌入，透传给 DeepSeekClient.embed
    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        try await client.embed(texts: texts, apiKey: apiKey)
    }

    /// 批量嵌入，按 batchSize 分片调用 embed，聚合结果。默认 batchSize=16（DeepSeek API 单次嵌入上限）。
    func embedBatch(_ texts: [String], batchSize: Int = 16, apiKey: String) async throws -> [[Float]] {
        var allEmbeddings: [[Float]] = []
        for batch in texts.chunked(into: batchSize) {
            let embeddings = try await embed(texts: batch, apiKey: apiKey)
            allEmbeddings.append(contentsOf: embeddings)
        }
        return allEmbeddings
    }
}

extension Array {
    /// 按 size 分片数组，最后一片可能不足 size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
