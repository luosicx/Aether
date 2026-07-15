import Foundation
import AetherRustC

/// Swift 友好的 Rust 向量数学包装。
///
/// 将 SemanticCache / RAGService / MemoryService 三处重复的 cosine 实现统一到 Rust，
/// 并移出 @MainActor 阻塞主线程。cosine 直接返回标量（无字符串分配）；
/// topK 因 corpus 为变长二维数组，用 JSON 进出。
public enum AetherRustVector {
    /// f32 余弦相似度（SemanticCache / RAGService 用）。长度不等或空返回 0。
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return a.withUnsafeBufferPointer { aBuf in
            b.withUnsafeBufferPointer { bBuf in
                aether_cosine_f32(aBuf.baseAddress, UInt(aBuf.count), bBuf.baseAddress, UInt(bBuf.count))
            }
        }
    }

    /// f64 余弦相似度（MemoryService 用，因 Memory.embedding: [Double]）。长度不等或空返回 0。
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return a.withUnsafeBufferPointer { aBuf in
            b.withUnsafeBufferPointer { bBuf in
                aether_cosine_f64(aBuf.baseAddress, UInt(aBuf.count), bBuf.baseAddress, UInt(bBuf.count))
            }
        }
    }

    /// top-K 检索：在 corpus 中找出与 query 最相似的 K 项。
    /// - Returns: `(index, score)` 数组，按 score 降序，长度 ≤ k。
    public static func topK(query: [Float], corpus: [[Float]], k: Int) -> [(index: Int, score: Float)] {
        guard k > 0, !corpus.isEmpty else { return [] }
        let input = TopKInput(query: query, corpus: corpus, k: k)
        guard let jsonData = try? JSONEncoder().encode(input),
              let json = String(data: jsonData, encoding: .utf8) else { return [] }
        guard let raw = json.withCString({ aether_top_k_f32_json($0) }) else { return [] }
        defer { aether_free_string(raw) }
        guard let result = String(cString: raw, encoding: .utf8),
              let data = result.data(using: .utf8),
              let pairs = try? JSONDecoder().decode([TopKPair].self, from: data) else { return [] }
        return pairs.map { (index: $0.index, score: $0.score) }
    }
}

/// topK 请求体（序列化为 Rust FFI 期望的 JSON）。
private struct TopKInput: Encodable {
    let query: [Float]
    let corpus: [[Float]]
    let k: Int
}

/// topK 响应项（Rust 返回 `[[index, score], ...]`）。
private struct TopKPair: Decodable {
    let index: Int
    let score: Float

    // JSON 数组解码：使用 UnkeyedContainer，无需 CodingKeys
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        index = try c.decode(Int.self)
        score = try c.decode(Float.self)
    }
}
