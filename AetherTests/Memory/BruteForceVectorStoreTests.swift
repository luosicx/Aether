import XCTest
@testable import Aether

/// Task 19 阶段 1: BruteForceVectorStore 单元测试。
///
/// 覆盖：插入/查询/删除/批量/计数/降级容错。纯内存实现，无系统依赖，CI 可直接运行。
final class BruteForceVectorStoreTests: XCTestCase {
    private var store: BruteForceVectorStore!

    override func setUp() async throws {
        try await super.setUp()
        store = BruteForceVectorStore()
        try await store.initialize()
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - 基本属性

    /// 暴力扫描存储恒可用
    func testIsAlwaysAvailable() async throws {
        XCTAssertTrue(await store.isAvailable, "BruteForceVectorStore 应恒为可用")
    }

    /// 初始化后应为空
    func testInitializeEmpty() async throws {
        let count = try await store.count()
        XCTAssertEqual(count, 0, "初始化后应为空")
    }

    // MARK: - 插入与查询

    /// 单条插入后应能查询到
    func testUpsertAndQuery() async throws {
        let id = UUID()
        let embedding: [Double] = [1.0, 0.0, 0.0]
        let metadata: [String: String] = ["category": "fact", "importance": "0.5", "content": "用户是素食者"]

        try await store.upsert(id: id, embedding: embedding, metadata: metadata)

        let results = try await store.query([1.0, 0.0, 0.0], limit: 5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, id)
        XCTAssertEqual(results.first?.similarity, 1.0, accuracy: 0.0001)
        XCTAssertEqual(results.first?.metadata["content"], "用户是素食者")
    }

    /// 查询应按相似度降序返回
    func testQueryReturnsBySimilarityOrder() async throws {
        try await store.upsert(id: UUID(), embedding: [1.0, 0.0, 0.0], metadata: [:])
        try await store.upsert(id: UUID(), embedding: [0.7, 0.7, 0.0], metadata: [:])
        try await store.upsert(id: UUID(), embedding: [0.0, 1.0, 0.0], metadata: [:])

        let results = try await store.query([1.0, 0.0, 0.0], limit: 3)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].similarity, 1.0, accuracy: 0.001, "最相似应排第一")
        XCTAssertLessThan(results[1].similarity, results[0].similarity, "中间相似度")
        XCTAssertLessThan(results[2].similarity, results[1].similarity, "最不相似应排最后")
    }

    /// limit 应限制返回条数
    func testQueryRespectsLimit() async throws {
        for _ in 0..<5 {
            try await store.upsert(id: UUID(), embedding: [1.0, 0.0, 0.0], metadata: [:])
        }
        let results = try await store.query([1.0, 0.0, 0.0], limit: 2)
        XCTAssertEqual(results.count, 2)
    }

    /// 空查询应返回空数组
    func testQueryEmptyReturnsEmpty() async throws {
        try await store.upsert(id: UUID(), embedding: [1.0, 0.0], metadata: [:])
        let results = try await store.query([], limit: 5)
        XCTAssertEqual(results.count, 0)
    }

    /// 维度不匹配应返回 0 相似度
    func testQueryDimensionMismatchReturnsZero() async throws {
        try await store.upsert(id: UUID(), embedding: [1.0, 0.0, 0.0], metadata: [:])
        let results = try await store.query([1.0, 0.0], limit: 5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.similarity, 0.0, "维度不匹配应返回 0")
    }

    // MARK: - 批量插入

    /// 批量插入应正确
    func testUpsertBatch() async throws {
        let records: [(id: UUID, embedding: [Double], metadata: [String: String])] = [
            (UUID(), [1.0, 0.0], ["category": "fact"]),
            (UUID(), [0.0, 1.0], ["category": "preference"]),
            (UUID(), [0.0, 0.0], ["category": "instruction"]),
        ]
        try await store.upsertBatch(records)
        let count = try await store.count()
        XCTAssertEqual(count, 3)
    }

    /// 重复 ID upsert 应覆盖
    func testUpsertOverwritesExisting() async throws {
        let id = UUID()
        try await store.upsert(id: id, embedding: [1.0, 0.0], metadata: ["content": "v1"])
        try await store.upsert(id: id, embedding: [0.0, 1.0], metadata: ["content": "v2"])

        let count = try await store.count()
        XCTAssertEqual(count, 1, "同 ID upsert 应覆盖")

        let results = try await store.query([0.0, 1.0], limit: 5)
        XCTAssertEqual(results.first?.metadata["content"], "v2", "应保留最新版本")
    }

    // MARK: - 删除

    /// 按 ID 删除
    func testDelete() async throws {
        let id = UUID()
        try await store.upsert(id: id, embedding: [1.0, 0.0], metadata: [:])
        XCTAssertEqual(try await store.count(), 1)

        try await store.delete(id: id)
        XCTAssertEqual(try await store.count(), 0)
    }

    /// 删除不存在的 ID 应幂等
    func testDeleteNonExistentIsIdempotent() async throws {
        try await store.delete(id: UUID())
        XCTAssertEqual(try await store.count(), 0)
    }

    /// 全部删除
    func testDeleteAll() async throws {
        for _ in 0..<3 {
            try await store.upsert(id: UUID(), embedding: [1.0, 0.0], metadata: [:])
        }
        try await store.deleteAll()
        XCTAssertEqual(try await store.count(), 0)
    }

    // MARK: - 相似度计算（共享静态方法）

    /// 相同向量相似度应为 1.0
    func testCosineSimilarityIdenticalVectors() {
        let sim = BruteForceVectorStore.cosineSimilarity([1.0, 2.0, 3.0], [1.0, 2.0, 3.0])
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001)
    }

    /// 正交向量相似度应为 0
    func testCosineSimilarityOrthogonalVectors() {
        let sim = BruteForceVectorStore.cosineSimilarity([1.0, 0.0], [0.0, 1.0])
        XCTAssertEqual(sim, 0.0, accuracy: 0.0001)
    }

    /// 长度不等的向量应返回 0
    func testCosineSimilarityDifferentLengths() {
        let sim = BruteForceVectorStore.cosineSimilarity([1.0, 2.0, 3.0], [1.0, 2.0])
        XCTAssertEqual(sim, 0.0)
    }

    /// 空向量应返回 0
    func testCosineSimilarityEmptyVectors() {
        XCTAssertEqual(BruteForceVectorStore.cosineSimilarity([], []), 0.0)
        XCTAssertEqual(BruteForceVectorStore.cosineSimilarity([1.0], []), 0.0)
    }
}
