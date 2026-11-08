import Foundation

// MARK: - BM25Retriever

/// v3.0: 本地 RAG 增强检索 — BM25 关键词检索引擎。
///
/// 职责：
/// - 基于 TF-IDF + BM25 算法的关键词检索
/// - 与向量检索互补，用于混合检索（Hybrid Retrieval）
/// - 纯内存实现（骨架），后续可扩展 SQLite FTS5 后端
///
/// 算法：
/// - BM25(q, d) = Σ IDF(qi) * (f(qi,d) * (k1+1)) / (f(qi,d) + k1*(1-b+b*|d|/avgdl))
/// - IDF(qi) = ln((N - n(qi) + 0.5) / (n(qi) + 0.5) + 1)
/// - k1=1.5, b=0.75（标准参数）
public final class BM25Retriever {

    /// BM25 文档表示
    public struct BM25Document: Sendable {
        public let id: String
        public let tokens: [String]
        public var termFreq: [String: Int]
        public var docLength: Int { tokens.count }

        public init(id: String, tokens: [String]) {
            self.id = id
            self.tokens = tokens
            // 构建词频表
            var freq: [String: Int] = [:]
            for token in tokens {
                freq[token, default: 0] += 1
            }
            self.termFreq = freq
        }
    }

    /// BM25 检索结果
    public struct BM25Result: Sendable {
        public let documentId: String
        public let score: Double
    }

    // MARK: - 参数

    /// k1 参数：词频饱和因子（1.2~2.0，默认 1.5）
    private let k1: Double
    /// b 参数：文档长度归一化因子（0~1，默认 0.75）
    private let b: Double

    // MARK: - 索引状态

    private(set) var documents: [BM25Document] = []
    private(set) var documentFrequency: [String: Int] = [:]  // 每个 token 出现在多少文档
    private(set) var totalDocLength: Int = 0
    private(set) var averageDocLength: Double = 0

    /// 初始化 BM25 检索器
    /// - Parameters:
    ///   - k1: 词频饱和因子，默认 1.5
    ///   - b: 文档长度归一化因子，默认 0.75
    public init(k1: Double = 1.5, b: Double = 0.75) {
        self.k1 = k1
        self.b = b
    }

    // MARK: - 索引管理

    /// 添加文档到索引
    public func addDocument(id: String, text: String) {
        let tokens = tokenize(text)
        let doc = BM25Document(id: id, tokens: tokens)
        documents.append(doc)
        totalDocLength += tokens.count
        // 更新文档频率
        for token in Set(tokens) {
            documentFrequency[token, default: 0] += 1
        }
        updateAverageDocLength()
    }

    /// 批量添加文档
    public func addDocuments(_ docs: [(id: String, text: String)]) {
        for (id, text) in docs {
            addDocument(id: id, text: text)
        }
    }

    /// 清空索引
    public func clear() {
        documents.removeAll()
        documentFrequency.removeAll()
        totalDocLength = 0
        averageDocLength = 0
    }

    /// 当前索引文档数
    public var documentCount: Int { documents.count }

    // MARK: - 检索

    /// 检索与查询最相关的 TopK 文档
    /// - Parameters:
    ///   - query: 查询文本
    ///   - topK: 返回结果数
    /// - Returns: 按分数降序排列的结果
    public func search(query: String, topK: Int = 10) -> [BM25Result] {
        let queryTokens = tokenize(query)
        guard !documents.isEmpty, !queryTokens.isEmpty else { return [] }

        let results = documents.map { doc -> BM25Result in
            BM25Result(documentId: doc.id, score: bm25Score(queryTokens: queryTokens, doc: doc))
        }

        return results.sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }

    // MARK: - BM25 评分

    /// 计算 BM25 分数
    private func bm25Score(queryTokens: [String], doc: BM25Document) -> Double {
        let n = Double(documents.count)
        var score: Double = 0

        for token in queryTokens {
            let df = Double(documentFrequency[token] ?? 0)
            // IDF
            let idf = log((n - df + 0.5) / (df + 0.5) + 1)
            // TF
            let tf = Double(doc.termFreq[token] ?? 0)
            guard tf > 0 else { continue }
            // BM25 TF
            let dl = Double(doc.docLength)
            let tfComponent = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / max(averageDocLength, 1)))
            score += idf * tfComponent
        }
        return score
    }

    // MARK: - 工具方法

    /// 简单分词：按空格与标点切分，转小写
    private func tokenize(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// 更新平均文档长度
    private func updateAverageDocLength() {
        guard !documents.isEmpty else {
            averageDocLength = 0
            return
        }
        averageDocLength = Double(totalDocLength) / Double(documents.count)
    }
}
