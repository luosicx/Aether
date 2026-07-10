import XCTest
import SwiftData
@testable import Aether

/// Day 11: RAGService 单元测试
@MainActor
final class RAGServiceTests: XCTestCase {

    // MARK: - 桩 EmbeddingService

    /// 桩子类：默认返回固定向量 [1,0,0]（保证 cosine 相似度=1，topK 截断生效）；
    /// 可配置 returnEmpty 模拟空 embedding。
    final class StubEmbeddingService: EmbeddingService {
        var returnEmpty = false

        override func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            if returnEmpty { return [] }
            return texts.map { _ in [Float(1.0), 0.0, 0.0] }
        }
    }

    // MARK: - 公共 setUp / tearDown

    private var container: ModelContainer!
    private var context: ModelContext!
    private var stub: StubEmbeddingService!
    private var service: RAGService!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: DocumentChunk.self, configurations: config)
        context = ModelContext(container)
        stub = StubEmbeddingService()
        service = RAGService(embeddingService: stub)
    }

    override func tearDown() {
        container = nil
        context = nil
        stub = nil
        service = nil
        super.tearDown()
    }

    // MARK: - indexDocument

    func testIndexDocumentSameSourceDedup() async throws {
        // v1：较长文本
        // 注意：DocumentChunker 切分行为依赖 NLTokenizer.unit = .sentence，
        // 在 iOS 模拟器上对重复英文文本可能不分句，导致 v1 / v2 都只产生 1 块。
        // 此处改为验证 indexDocument 调用不 crash + 至少返回 1 块（接口契约）。
        let sentence = (0..<40).map { _ in "word" }.joined(separator: " ") + "."
        let textV1 = (0..<30).map { _ in sentence }.joined(separator: " ")
        try await service.indexDocument(text: textV1, source: "doc.txt", modelContext: context, apiKey: "key")
        let countV1 = try context.fetch(FetchDescriptor<DocumentChunk>()).count
        XCTAssertGreaterThanOrEqual(countV1, 1, "v1 至少应索引 1 块（DocumentChunker 切分依赖 NLTokenizer）")

        // v2：较短文本，同 source（验证同 source 二次 index 不 crash）
        let textV2 = (0..<15).map { _ in sentence }.joined(separator: " ")
        try await service.indexDocument(text: textV2, source: "doc.txt", modelContext: context, apiKey: "key")
        let countV2 = try context.fetch(FetchDescriptor<DocumentChunk>()).count
        XCTAssertGreaterThanOrEqual(countV2, 1, "v2 至少应索引 1 块（DocumentChunker 切分依赖 NLTokenizer）")

        // 验证同 source 二次 index 后只剩 v2 的块数（去重生效）
        let expectedV2 = DocumentChunker().chunkDocument(textV2, source: "doc.txt").count
        XCTAssertEqual(countV2, expectedV2, "同 source 二次 index 应删除旧 chunks，只剩 v2 的块数")
    }

    func testIndexDocumentEmptyChunksReturns() async throws {
        // 空文本 → chunkDocument 返回空 → 提前 return，不创建任何 chunk
        try await service.indexDocument(text: "", source: "empty.txt", modelContext: context, apiKey: "key")
        let count = try context.fetch(FetchDescriptor<DocumentChunk>()).count
        XCTAssertEqual(count, 0, "空 chunks 应提前返回，不创建任何记录")
    }

    // MARK: - retrieve

    func testRetrieveTopKTruncation() async throws {
        // 直接插入 5 个 chunk，避免依赖 DocumentChunker 切分行为
        // （NLTokenizer 在 iOS 模拟器上可能不切分重复英文文本，导致只产生 1 块）
        // stub embedding 返回 [1.0, 0.0, 0.0]，此处 chunk embedding 也用同向量，
        // cosine similarity = 1.0（完全匹配），应全部命中。
        for i in 0..<5 {
            let chunk = DocumentChunk(content: "chunk \(i)", embedding: [Float(1.0), 0.0, 0.0], source: "doc.txt", chunkIndex: i)
            chunk.createdAt = Date()
            context.insert(chunk)
        }
        try context.save()

        let retrieved = try await service.retrieve(query: "query", topK: 3, modelContext: context, apiKey: "key")
        XCTAssertEqual(retrieved.count, 3, "topK=3 应返回 3 块")
    }

    func testRetrieveEmptyEmbeddingReturnsEmpty() async throws {
        stub.returnEmpty = true
        let retrieved = try await service.retrieve(query: "query", topK: 3, modelContext: context, apiKey: "key")
        XCTAssertTrue(retrieved.isEmpty, "query embedding 为空时应返回空")
    }

    // MARK: - buildAugmentedContext

    func testBuildAugmentedContextEmptyStore() async throws {
        // 空库 + 空 embedding → 第一道 guard 触发，返回 ("", [], [])
        stub.returnEmpty = true
        let result = try await service.buildAugmentedContext(query: "query", modelContext: context, apiKey: "key")
        XCTAssertEqual(result.context, "", "空 embedding 时 context 应为空")
        XCTAssertTrue(result.citations.isEmpty, "空 embedding 时 citations 应为空")
        XCTAssertTrue(result.queryEmbedding.isEmpty, "空 embedding 时 queryEmbedding 应为空")
    }

    func testBuildAugmentedContextNoRelevantChunks() async throws {
        // 空库 + 非空 embedding → 第二道 guard 触发（无相关块），返回 ("", [], embedding)
        let result = try await service.buildAugmentedContext(query: "query", modelContext: context, apiKey: "key")
        XCTAssertEqual(result.context, "", "无相关块时 context 应为空")
        XCTAssertTrue(result.citations.isEmpty, "无相关块时 citations 应为空")
        XCTAssertEqual(result.queryEmbedding, [1.0, 0.0, 0.0], "应返回 query embedding")
    }

    func testBuildAugmentedContextNumbering() async throws {
        // 直接插入 2 个 chunk，避免依赖 DocumentChunker 切分行为
        // （NLTokenizer 在 iOS 模拟器上可能不切分重复英文文本，导致只产生 1 块）
        // stub embedding 返回 [1.0, 0.0, 0.0]，此处 chunk embedding 也用同向量，
        // cosine similarity = 1.0（完全匹配），应命中。
        for i in 1...2 {
            let chunk = DocumentChunk(content: "内容\(i)", embedding: [Float(1.0), 0.0, 0.0], source: "doc.txt", chunkIndex: i - 1)
            chunk.createdAt = Date()
            context.insert(chunk)
        }
        try context.save()

        let result = try await service.buildAugmentedContext(query: "query", modelContext: context, apiKey: "key")
        XCTAssertFalse(result.context.isEmpty, "有相关块时 context 应非空")
        XCTAssertTrue(result.context.contains("[1]"), "prompt 应含 [1] 编号")
        XCTAssertTrue(result.context.contains("[2]"), "prompt 应含 [2] 编号")
        XCTAssertFalse(result.citations.isEmpty, "应返回 citations")
    }

    // MARK: - Day 12: weight 权重

    func testRetrieveRespectsChunkWeight() async throws {
        // 插入两个 cosine 相同的 chunk（StubEmbeddingService 总是返回 [1,0,0]，所有 chunk 的 cosine=1.0）
        // 一个 weight=1.0（默认），一个 weight=0.5
        // topK=1 时应返回 weight=1.0 的 chunk（因为 score = cosine * weight）
        let highWeightChunk = DocumentChunk(
            content: "高权重块", embedding: [Float(1.0), 0.0, 0.0],
            source: "doc.txt", chunkIndex: 0
        )
        // highWeightChunk.weight 默认 1.0
        context.insert(highWeightChunk)

        let lowWeightChunk = DocumentChunk(
            content: "低权重块", embedding: [Float(1.0), 0.0, 0.0],
            source: "doc.txt", chunkIndex: 1
        )
        lowWeightChunk.weight = 0.5
        context.insert(lowWeightChunk)
        try context.save()

        let retrieved = try await service.retrieve(query: "query", topK: 1, modelContext: context, apiKey: "key")
        XCTAssertEqual(retrieved.count, 1, "topK=1 应只返回 1 块")
        XCTAssertEqual(retrieved.first?.content, "高权重块", "应返回 weight 更高的 chunk（score = cosine * weight）")
    }
}
