import Foundation

// MARK: - CrossEncoderReranker

/// v3.0: 本地 RAG 增强检索 — Cross-Encoder 重排序器。
///
/// 职责：
/// - 对向量检索 + BM25 检索的 TopK 结果进行重排序
/// - 基于 Cross-Encoder（如 ms-marco-MiniLM-L-12）计算 query-doc 精细相关度
/// - 目标：Recall@5 ≥0.85，推理延迟 ≤200ms
///
/// 当前状态：
/// - v3.0 骨架实现，返回基于交叉特征的启发式评分
/// - 待 ONNX Runtime Swift 包集成后替换为真实模型推理
public final class CrossEncoderReranker {

    /// 重排序结果
    public struct RerankResult: Sendable {
        public let documentId: String
        public let score: Double
    }

    /// 是否启用真实模型推理（false = 启发式占位）
    public let modelLoaded: Bool

    /// 模型名称
    public let modelName: String

    /// 初始化
    /// - Parameter modelName: Cross-Encoder 模型名，默认 ms-marco-MiniLM-L-12
    public init(modelName: String = "ms-marco-MiniLM-L-12") {
        self.modelName = modelName
        // v3.0 骨架：ONNX Runtime 集成后此处加载量化模型
        self.modelLoaded = false
    }

    /// 重排序：对 (query, document) 对列表计算相关度并排序
    /// - Parameters:
    ///   - query: 用户查询
    ///   - documents: 待排序的 (id, text) 列表
    ///   - topK: 返回前 K 个
    /// - Returns: 按相关度降序排列的结果
    public func rerank(query: String, documents: [(id: String, text: String)], topK: Int = 5) -> [RerankResult] {
        let results = documents.map { (id, text) -> RerankResult in
            RerankResult(documentId: id, score: crossEncoderScore(query: query, document: text))
        }
        return results.sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }

    /// Cross-Encoder 评分（启发式占位）
    /// v3.0 骨架：实际调用 ONNX Runtime 推理，当前用交叉特征近似
    private func crossEncoderScore(query: String, document: String) -> Double {
        let queryTokens = Set(query.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let docTokens = document.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        guard !queryTokens.isEmpty, !docTokens.isEmpty else { return 0 }

        // 精确匹配率
        let docTokenSet = Set(docTokens)
        let exactMatches = queryTokens.intersection(docTokenSet).count
        let matchRatio = Double(exactMatches) / Double(queryTokens.count)

        // 长度归一化（避免短文档得分偏高）
        let lengthPenalty = 1.0 / (1.0 + log(Double(docTokens.count)))

        // 组合评分：匹配率 * 0.8 + 长度惩罚 * 0.2
        return matchRatio * 0.8 + lengthPenalty * 0.2
    }
}
