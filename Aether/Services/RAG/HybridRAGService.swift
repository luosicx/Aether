import Foundation

// MARK: - HybridRAGService

/// v3.0: 本地 RAG 增强检索 — 混合检索服务。
///
/// 职责：
/// - 整合向量检索 + BM25 关键词检索
/// - 使用 RRF（Reciprocal Rank Fusion）融合两路结果
/// - 调用 Cross-Encoder 对融合结果重排序
/// - 支持查询改写（同义词扩展 / HyDE）
///
/// 算法流程：
/// 1. 向量检索 TopK=20（由 RAGService 提供）
/// 2. BM25 检索 TopK=20（由 BM25Retriever 提供）
/// 3. RRF 融合 → TopK=10
/// 4. Cross-Encoder 重排序 → TopK=5
///
/// RRF 公式：score(d) = Σ 1 / (k + rank_i(d))，k=60（标准参数）
public final class HybridRAGService {

    /// 混合检索结果
    public struct HybridResult: Sendable {
        public let documentId: String
        public let text: String
        public let vectorScore: Double
        public let bm25Score: Double
        public let fusedScore: Double
        public let rerankedScore: Double

        public init(documentId: String, text: String, vectorScore: Double, bm25Score: Double, fusedScore: Double, rerankedScore: Double) {
            self.documentId = documentId
            self.text = text
            self.vectorScore = vectorScore
            self.bm25Score = bm25Score
            self.fusedScore = fusedScore
            self.rerankedScore = rerankedScore
        }
    }

    // MARK: - 依赖

    /// BM25 检索器
    private let bm25Retriever: BM25Retriever
    /// Cross-Encoder 重排序器
    private let reranker: CrossEncoderReranker

    /// RRF 参数 k（默认 60）
    private let rrfK: Double

    /// 初始化
    /// - Parameters:
    ///   - bm25Retriever: BM25 检索器，可注入
    ///   - reranker: 重排序器，可注入
    ///   - rrfK: RRF 融合参数，默认 60
    public init(
        bm25Retriever: BM25Retriever = BM25Retriever(),
        reranker: CrossEncoderReranker = CrossEncoderReranker(),
        rrfK: Double = 60
    ) {
        self.bm25Retriever = bm25Retriever
        self.reranker = reranker
        self.rrfK = rrfK
    }

    // MARK: - 索引管理

    /// 索引文档（同时写入 BM25 索引；向量索引由 RAGService 管理）
    public func indexDocument(id: String, text: String) {
        bm25Retriever.addDocument(id: id, text: text)
    }

    /// 批量索引
    public func indexDocuments(_ docs: [(id: String, text: String)]) {
        for (id, text) in docs {
            indexDocument(id: id, text: text)
        }
    }

    /// 清空索引
    public func clear() {
        bm25Retriever.clear()
    }

    // MARK: - 内部类型

    /// RRF 融合中间结果（避免 large_tuple 规则）
    private struct FusedItem {
        let id: String
        let text: String
        let vectorScore: Double
        let bm25Score: Double
        let fusedScore: Double
    }

    // MARK: - 混合检索

    /// 执行混合检索
    /// - Parameters:
    ///   - query: 用户查询
    ///   - vectorResults: 向量检索结果（id, text, score）
    ///   - topK: 最终返回结果数
    /// - Returns: 混合检索结果，按重排序分数降序
    public func hybridSearch(
        query: String,
        vectorResults: [(id: String, text: String, score: Double)],
        topK: Int = 5
    ) -> [HybridResult] {
        // 1. BM25 检索
        let bm25Results = bm25Retriever.search(query: query, topK: 20)
        let bm25Map = Dictionary(bm25Results.map { ($0.documentId, $0.score) }, uniquingKeysWith: { a, _ in a })

        // 2. RRF 融合
        let fused: [FusedItem] = vectorResults.prefix(20).enumerated().map { index, item in
            let vectorRank = Double(index + 1)
            let bm25Rank: Double
            if let idx = bm25Results.firstIndex(where: { $0.documentId == item.id }) {
                bm25Rank = Double(idx + 1)
            } else {
                bm25Rank = Double(bm25Results.count + 1)
            }
            let rrfScore = 1.0 / (rrfK + vectorRank) + 1.0 / (rrfK + bm25Rank)
            return FusedItem(
                id: item.id,
                text: item.text,
                vectorScore: item.score,
                bm25Score: bm25Map[item.id] ?? 0,
                fusedScore: rrfScore
            )
        }

        // 3. 取 Top10 进入重排序
        let top10ForRerank = fused.sorted { $0.fusedScore > $1.fusedScore }.prefix(10)

        // 4. Cross-Encoder 重排序
        let rerankInput = top10ForRerank.map { ($0.id, $0.text) }
        let rerankResults = reranker.rerank(query: query, documents: rerankInput, topK: topK)
        let rerankMap = Dictionary(rerankResults.map { ($0.documentId, $0.score) }, uniquingKeysWith: { a, _ in a })

        // 5. 组装最终结果
        return top10ForRerank.map { item in
            HybridResult(
                documentId: item.id,
                text: item.text,
                vectorScore: item.vectorScore,
                bm25Score: item.bm25Score,
                fusedScore: item.fusedScore,
                rerankedScore: rerankMap[item.id] ?? 0
            )
        }
        .sorted { $0.rerankedScore > $1.rerankedScore }
        .prefix(topK)
        .map { $0 }
    }

    // MARK: - 查询改写（占位）

    /// 查询改写：用 LLM 改写为多版本（同义词扩展 / HyDE 假设文档）
    /// v3.0 骨架：返回原始查询，待 LLM 集成后实现
    public func rewriteQuery(_ query: String) -> [String] {
        // 简单同义词扩展占位
        var variants: [String] = [query]
        // 简单扩展：去除问号、添加同义词
        let cleaned = query.replacingOccurrences(of: "?？", with: "")
        if cleaned != query {
            variants.append(cleaned)
        }
        return variants
    }
}
