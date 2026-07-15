import Foundation
import AetherFoundation
import AetherServices

/// 嵌入服务，封装 LLMProvider 的 embed 能力，提供批量分片聚合
class EmbeddingService {
    /// LLMProvider 实例（注意：class 非 final，允许测试子类化注入 stub）
    private let client: LLMProvider

    init(client: LLMProvider = DeepSeekClient()) {
        self.client = client
    }

    /// 解析可用于 embedding 的 Provider 与对应 client。
    /// DeepSeek API 不提供 embeddings 端点（返回 404），需降级到 Qwen。
    /// - DeepSeek：若 Keychain 有 Qwen API Key 则降级到 Qwen，否则返回 nil（调用方应提示用户配置）
    /// - Qwen / onDevice：直接使用该 Provider
    static func resolveEmbedding(for provider: ModelProvider) -> (LLMProvider, ModelProvider)? {
        switch provider {
        case .qwen, .onDevice:
            return (QwenClient(), provider)
        case .deepseek:
            let qwenKey = KeychainManager.shared.getAPIKey(for: .qwen) ?? ""
            guard !qwenKey.isEmpty else { return nil }
            return (QwenClient(), .qwen)
        }
    }

    /// 单次嵌入，透传给 LLMProvider.embed
    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        try await client.embed(texts: texts, apiKey: apiKey)
    }

    /// 批量嵌入，按 batchSize 分片调用 embed，聚合结果。默认 batchSize=10（Qwen API 单次嵌入行数上限）。
    func embedBatch(_ texts: [String], batchSize: Int = 10, apiKey: String) async throws -> [[Float]] {
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
