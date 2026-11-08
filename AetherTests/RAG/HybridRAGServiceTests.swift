import XCTest
@testable import Aether

/// v3.0: 混合 RAG 检索服务测试（含 BM25 + Cross-Encoder + RRF 融合）
final class HybridRAGServiceTests: XCTestCase {

    // MARK: - BM25Retriever 测试

    func testBM25InitDefaults() {
        let retriever = BM25Retriever()
        XCTAssertEqual(retriever.documentCount, 0, "初始文档数应为 0")
    }

    func testBM25AddDocument() {
        let retriever = BM25Retriever()
        retriever.addDocument(id: "doc1", text: "hello world")
        XCTAssertEqual(retriever.documentCount, 1, "添加后文档数应为 1")
    }

    func testBM25AddMultipleDocuments() {
        let retriever = BM25Retriever()
        retriever.addDocuments([
            ("doc1", "hello world"),
            ("doc2", "world peace"),
            ("doc3", "hello peace")
        ])
        XCTAssertEqual(retriever.documentCount, 3)
    }

    func testBM25SearchEmptyIndex() {
        let retriever = BM25Retriever()
        let results = retriever.search(query: "test", topK: 5)
        XCTAssertTrue(results.isEmpty, "空索引应返回空结果")
    }

    func testBM25SearchExactMatch() {
        let retriever = BM25Retriever()
        retriever.addDocument(id: "doc1", text: "the quick brown fox")
        retriever.addDocument(id: "doc2", text: "hello world")
        let results = retriever.search(query: "fox", topK: 2)
        XCTAssertEqual(results.first?.documentId, "doc1", "应匹配包含 fox 的文档")
        XCTAssertTrue(results.first?.score ?? 0 > 0, "分数应大于 0")
    }

    func testBM25SearchRankedResults() {
        let retriever = BM25Retriever()
        retriever.addDocument(id: "doc1", text: "machine learning is great")
        retriever.addDocument(id: "doc2", text: "machine learning and ai")
        retriever.addDocument(id: "doc3", text: "unrelated content")
        let results = retriever.search(query: "machine learning", topK: 3)
        XCTAssertEqual(results.count, 3)
        // doc3 应排在最后（分数最低）
        XCTAssertEqual(results.last?.documentId, "doc3")
    }

    func testBM25SearchTopK() {
        let retriever = BM25Retriever()
        for i in 0..<10 {
            retriever.addDocument(id: "doc\(i)", text: "document number \(i) with some content")
        }
        let results = retriever.search(query: "document", topK: 5)
        XCTAssertEqual(results.count, 5, "应返回 5 个结果")
    }

    func testBM25Clear() {
        let retriever = BM25Retriever()
        retriever.addDocument(id: "doc1", text: "test")
        retriever.clear()
        XCTAssertEqual(retriever.documentCount, 0, "清空后文档数应为 0")
    }

    func testBM25CustomParameters() {
        let retriever = BM25Retriever(k1: 2.0, b: 0.5)
        retriever.addDocument(id: "doc1", text: "test content")
        let results = retriever.search(query: "test", topK: 1)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - CrossEncoderReranker 测试

    func testRerankerInit() {
        let reranker = CrossEncoderReranker()
        XCTAssertFalse(reranker.modelLoaded, "骨架模式 modelLoaded 应为 false")
        XCTAssertEqual(reranker.modelName, "ms-marco-MiniLM-L-12")
    }

    func testRerankerCustomModel() {
        let reranker = CrossEncoderReranker(modelName: "custom-reranker")
        XCTAssertEqual(reranker.modelName, "custom-reranker")
    }

    func testRerankerEmptyInput() {
        let reranker = CrossEncoderReranker()
        let results = reranker.rerank(query: "test", documents: [], topK: 5)
        XCTAssertTrue(results.isEmpty, "空输入应返回空结果")
    }

    func testRerankerScoresDocuments() {
        let reranker = CrossEncoderReranker()
        let docs = [
            (id: "d1", text: "machine learning overview"),
            (id: "d2", text: "cooking recipes")
        ]
        let results = reranker.rerank(query: "machine learning", documents: docs, topK: 2)
        XCTAssertEqual(results.count, 2)
        // 机器学习相关文档应排前面
        XCTAssertEqual(results.first?.documentId, "d1")
    }

    func testRerankerTopKLimit() {
        let reranker = CrossEncoderReranker()
        let docs = (0..<10).map { (id: "d\($0)", text: "document \($0)") }
        let results = reranker.rerank(query: "document", documents: docs, topK: 3)
        XCTAssertEqual(results.count, 3)
    }

    func testRerankerScoresDescending() {
        let reranker = CrossEncoderReranker()
        let docs = [
            (id: "d1", text: "apple banana cherry"),
            (id: "d2", text: "apple"),
            (id: "d3", text: "zebra")
        ]
        let results = reranker.rerank(query: "apple banana", documents: docs, topK: 3)
        // 分数应降序排列
        for i in 0..<results.count-1 {
            XCTAssertGreaterThanOrEqual(results[i].score, results[i+1].score)
        }
    }

    // MARK: - HybridRAGService 测试

    func testHybridInit() {
        let service = HybridRAGService()
        XCTAssertNotNil(service)
    }

    func testHybridIndexDocument() {
        let service = HybridRAGService()
        service.indexDocument(id: "doc1", text: "test document")
        // 索引后应可检索
        let results = service.hybridSearch(
            query: "test",
            vectorResults: [("doc1", "test document", 0.9)],
            topK: 1
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.documentId, "doc1")
    }

    func testHybridSearchEmptyVectorResults() {
        let service = HybridRAGService()
        service.indexDocument(id: "doc1", text: "test")
        let results = service.hybridSearch(query: "nonexistent", vectorResults: [], topK: 5)
        // 向量结果为空时，仅 BM25 结果参与融合
        XCTAssertTrue(results.count <= 1)
    }

    func testHybridSearchFusion() {
        let service = HybridRAGService()
        service.indexDocuments([
            ("doc1", "machine learning fundamentals"),
            ("doc2", "deep learning tutorial"),
            ("doc3", "unrelated content")
        ])
        let vectorResults: [(id: String, text: String, score: Double)] = [
            ("doc1", "machine learning fundamentals", 0.9),
            ("doc2", "deep learning tutorial", 0.8),
            ("doc3", "unrelated content", 0.1)
        ]
        let results = service.hybridSearch(query: "machine learning", vectorResults: vectorResults, topK: 2)
        XCTAssertEqual(results.count, 2)
        // 应排除不相关文档
        XCTAssertFalse(results.contains(where: { $0.documentId == "doc3" }))
    }

    func testHybridResultContainsAllScores() {
        let service = HybridRAGService()
        service.indexDocument(id: "doc1", text: "test content")
        let results = service.hybridSearch(
            query: "test",
            vectorResults: [("doc1", "test content", 0.85)],
            topK: 1
        )
        XCTAssertEqual(results.count, 1)
        let r = results[0]
        XCTAssertNotNil(r.vectorScore)
        XCTAssertNotNil(r.bm25Score)
        XCTAssertNotNil(r.fusedScore)
        XCTAssertNotNil(r.rerankedScore)
        XCTAssertEqual(r.vectorScore, 0.85, accuracy: 0.001)
    }

    func testHybridRewriteQuery() {
        let service = HybridRAGService()
        let variants = service.rewriteQuery("什么是机器学习？")
        XCTAssertFalse(variants.isEmpty, "查询改写应返回至少原始查询")
        XCTAssertEqual(variants.first, "什么是机器学习？")
    }

    func testHybridRewriteQueryNoQuestionMark() {
        let service = HybridRAGService()
        let variants = service.rewriteQuery("机器学习")
        XCTAssertEqual(variants.count, 1, "无问号时应只返回原始查询")
    }

    func testHybridClear() {
        let service = HybridRAGService()
        service.indexDocument(id: "doc1", text: "test")
        service.clear()
        // 清空后检索应无 BM25 结果
        let results = service.hybridSearch(
            query: "test",
            vectorResults: [("doc1", "test", 0.9)],
            topK: 5
        )
        // 向量结果仍参与融合
        XCTAssertFalse(results.isEmpty)
    }

    func testHybridCustomRRF() {
        let service = HybridRAGService(rrfK: 30)
        service.indexDocument(id: "doc1", text: "test")
        let results = service.hybridSearch(
            query: "test",
            vectorResults: [("doc1", "test", 0.9)],
            topK: 1
        )
        XCTAssertEqual(results.count, 1)
    }
}
