import XCTest
@testable import Aether

/// Task 19 阶段 2: RecallEngine 单元测试。
///
/// 覆盖：复合评分正确性、时间衰减（30 天半衰期）、同类别去重、用户主动记忆不衰减、
/// top-K 限制、空输入处理、lastAccessedAt 更新、VectorStore 不可用时回退到暴力扫描。
@MainActor
final class RecallEngineTests: XCTestCase {
    private var factory: VectorStoreFactory!

    override func setUp() async throws {
        try await super.setUp()
        // 每个测试使用独立 factory，避免污染单例
        factory = VectorStoreFactory()
        factory.reset()
    }

    override func tearDown() async throws {
        factory.reset()
        factory = nil
        try await super.tearDown()
    }

    // MARK: - 静态评分函数

    /// 相似度=1.0、importance=0.5、recency=1.0 的复合分应为 0.6×1 + 0.3×0.5 + 0.1×1 = 0.85
    func testComputeFinalScoreWithFullSimilarity() {
        let memory = Memory(content: "测试", embedding: [1, 0], category: "context", importance: 0.5)
        let now = Date()
        let score = RecallEngine.computeFinalScore(memory: memory, similarity: 1.0, now: now)
        XCTAssertEqual(score, 0.85, accuracy: 0.0001, "0.6×1 + 0.3×0.5 + 0.1×1 应为 0.85")
    }

    /// 相似度=0.0、importance=0.0、recency=0.0（30+ 半衰期后）的复合分应为 0.0
    func testComputeFinalScoreWithZeroInputs() {
        let memory = Memory(content: "测试", embedding: [1, 0], category: "context", importance: 0.0)
        // 让 lastAccessedAt 远在过去使 recency→0（取 1 年前）
        let past = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        memory.lastAccessedAt = past
        let now = Date()
        let score = RecallEngine.computeFinalScore(memory: memory, similarity: 0.0, now: now)
        XCTAssertLessThan(score, 0.001, "全 0 输入应接近 0")
    }

    /// 用户主动记忆 recency 应恒为 1.0（不随时间衰减）
    func testUserExplicitMemoryNoDecay() {
        let memory = Memory(content: "用户主动", embedding: [1, 0], category: "preference", importance: 0.8, isUserExplicit: true)
        let now = Date()
        let score = RecallEngine.computeFinalScore(memory: memory, similarity: 1.0, now: now)
        // 0.6×1 + 0.3×0.8 + 0.1×1 = 0.94
        XCTAssertEqual(score, 0.94, accuracy: 0.0001, "用户主动记忆 importance=0.8、recency=1.0、sim=1.0 应为 0.94")
    }

    /// 时间衰减：30 天前访问的记忆 recency 应为 0.5（半衰期）
    func testTimeDecayHalfLife() {
        let memory = Memory(content: "测试", embedding: [1, 0], category: "context", importance: 0.5)
        let now = Date()
        // 30 天前访问
        let past = now.addingTimeInterval(-30 * 24 * 60 * 60)
        memory.lastAccessedAt = past
        let recency = RecallEngine.computeRecency(memory: memory, now: now)
        XCTAssertEqual(recency, 0.5, accuracy: 0.05, "30 天半衰期，Δt=30天时 recency 应≈0.5")
    }

    /// 时间衰减：刚刚访问的记忆 recency 应为 1.0
    func testTimeDecayZeroDelta() {
        let memory = Memory(content: "测试", embedding: [1, 0], category: "context", importance: 0.5)
        let now = Date()
        memory.lastAccessedAt = now
        let recency = RecallEngine.computeRecency(memory: memory, now: now)
        XCTAssertEqual(recency, 1.0, accuracy: 0.0001, "Δt=0 时 recency 应为 1.0")
    }

    /// 时间衰减：无 lastAccessedAt 时回退到 createdAt
    func testTimeDecayFallbackToCreatedAt() {
        let memory = Memory(content: "测试", embedding: [1, 0], category: "context", importance: 0.5)
        // createdAt 在 init 时已设置为 Date()，Δt 接近 0
        let now = Date()
        let recency = RecallEngine.computeRecency(memory: memory, now: now)
        XCTAssertEqual(recency, 1.0, accuracy: 0.05, "无 lastAccessedAt 时回退到 createdAt，Δt≈0 时 recency≈1.0")
    }

    // MARK: - recall 主流程

    /// recall 应返回按复合评分降序排列的记忆
    func testRecallReturnsSortedByScore() async throws {
        let now = Date()
        // 构造两条记忆，A 高 importance 高相似度，B 低 importance 低相似度
        let memoryA = Memory(content: "A", embedding: [1, 0], category: "context", importance: 0.9)
        let memoryB = Memory(content: "B", embedding: [0, 1], category: "context", importance: 0.1)

        // 注入预填充 BruteForceVectorStore
        let store = BruteForceVectorStore()
        try await store.upsert(id: memoryA.id, embedding: memoryA.embedding, metadata: [:])
        try await store.upsert(id: memoryB.id, embedding: memoryB.embedding, metadata: [:])
        factory.setOverride(store)

        let engine = RecallEngine(vectorStoreFactory: factory)
        let results = await engine.recall(query: [1, 0], memories: [memoryA, memoryB], limit: 2, now: now)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.content, "A", "高相似度高 importance 的记忆应排首位")
    }

    /// recall limit 应限制返回条数
    func testRecallRespectsLimit() async throws {
        let memories = (0..<5).map { i in
            Memory(content: "记忆\(i)", embedding: [Double(i), 0], category: "context", importance: 0.5)
        }
        let store = BruteForceVectorStore()
        for m in memories {
            try await store.upsert(id: m.id, embedding: m.embedding, metadata: [:])
        }
        factory.setOverride(store)

        let engine = RecallEngine(vectorStoreFactory: factory)
        let results = await engine.recall(query: [1, 0], memories: memories, limit: 2)
        XCTAssertEqual(results.count, 2, "limit=2 应仅返回 2 条")
    }

    /// recall 应按 category 去重，同类别仅保留最高分
    func testRecallDedupesByCategory() async throws {
        // 两条 preference 类别（A 相似度高、B 低）、一条 fact 类别（C）
        let memoryA = Memory(content: "A", embedding: [1, 0], category: "preference", importance: 0.5)
        let memoryB = Memory(content: "B", embedding: [0.9, 0.1], category: "preference", importance: 0.5)
        let memoryC = Memory(content: "C", embedding: [0, 1], category: "fact", importance: 0.5)

        let store = BruteForceVectorStore()
        try await store.upsert(id: memoryA.id, embedding: memoryA.embedding, metadata: [:])
        try await store.upsert(id: memoryB.id, embedding: memoryB.embedding, metadata: [:])
        try await store.upsert(id: memoryC.id, embedding: memoryC.embedding, metadata: [:])
        factory.setOverride(store)

        let engine = RecallEngine(vectorStoreFactory: factory)
        let results = await engine.recall(query: [1, 0], memories: [memoryA, memoryB, memoryC], limit: 3)

        XCTAssertEqual(results.count, 2, "去重后应剩 2 条（preference + fact）")
        let categories = Set(results.map { $0.category })
        XCTAssertEqual(categories, ["preference", "fact"], "每个类别应仅保留一条")
        XCTAssertTrue(results.contains { $0.content == "A" }, "preference 类别应保留相似度更高的 A")
    }

    /// 用户主动记忆应在召回结果中保留（importance=0.8 加成）
    func testRecallKeepsUserExplicitMemory() async throws {
        let userExplicit = Memory(content: "用户主动", embedding: [0.5, 0.5], category: "preference", importance: 0.8, isUserExplicit: true)
        let normal = Memory(content: "普通记忆", embedding: [1, 0], category: "context", importance: 0.5)

        let store = BruteForceVectorStore()
        try await store.upsert(id: userExplicit.id, embedding: userExplicit.embedding, metadata: [:])
        try await store.upsert(id: normal.id, embedding: normal.embedding, metadata: [:])
        factory.setOverride(store)

        let engine = RecallEngine(vectorStoreFactory: factory)
        // 查询与普通记忆更相似，但用户主动记忆有 importance 加成
        let results = await engine.recall(query: [1, 0], memories: [userExplicit, normal], limit: 2)
        XCTAssertTrue(results.contains { $0.content == "用户主动" }, "用户主动记忆应出现在召回结果")
    }

    /// recall 应更新 lastAccessedAt
    func testRecallUpdatesLastAccessedAt() async throws {
        let memory = Memory(content: "测试", embedding: [1, 0], category: "context", importance: 0.5)
        XCTAssertNil(memory.lastAccessedAt, "初始 lastAccessedAt 应为 nil")

        let store = BruteForceVectorStore()
        try await store.upsert(id: memory.id, embedding: memory.embedding, metadata: [:])
        factory.setOverride(store)

        let engine = RecallEngine(vectorStoreFactory: factory)
        let now = Date()
        _ = await engine.recall(query: [1, 0], memories: [memory], limit: 1, now: now)

        XCTAssertNotNil(memory.lastAccessedAt, "召回后 lastAccessedAt 应被设置")
        XCTAssertEqual(memory.lastAccessedAt?.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001, "lastAccessedAt 应等于传入的 now")
    }

    /// 空查询应返回空数组
    func testRecallWithEmptyQueryReturnsEmpty() async throws {
        let engine = RecallEngine(vectorStoreFactory: factory)
        let memory = Memory(content: "测试", embedding: [1, 0])
        let results = await engine.recall(query: [], memories: [memory], limit: 5)
        XCTAssertEqual(results, [], "空查询应返回空数组")
    }

    /// 空记忆列表应返回空数组
    func testRecallWithEmptyMemoriesReturnsEmpty() async throws {
        let engine = RecallEngine(vectorStoreFactory: factory)
        let results = await engine.recall(query: [1, 0], memories: [], limit: 5)
        XCTAssertEqual(results, [], "空记忆列表应返回空数组")
    }

    /// 无 embedding 的记忆应被跳过
    func testRecallSkipsMemoriesWithoutEmbedding() async throws {
        let noEmbed = Memory(content: "无向量", embedding: [], category: "context", importance: 0.5)
        let hasEmbed = Memory(content: "有向量", embedding: [1, 0], category: "context", importance: 0.5)

        let store = BruteForceVectorStore()
        try await store.upsert(id: hasEmbed.id, embedding: hasEmbed.embedding, metadata: [:])
        factory.setOverride(store)

        let engine = RecallEngine(vectorStoreFactory: factory)
        let results = await engine.recall(query: [1, 0], memories: [noEmbed, hasEmbed], limit: 5)
        XCTAssertEqual(results.count, 1, "应仅返回有 embedding 的记忆")
        XCTAssertEqual(results.first?.content, "有向量")
    }

    /// VectorStore 不可用时（返回空结果），应回退到内存暴力扫描
    func testRecallFallsBackToBruteForceWhenStoreEmpty() async throws {
        // 注入空 store（query 返回空）
        let emptyStore = BruteForceVectorStore()
        factory.setOverride(emptyStore)

        let memory = Memory(content: "测试", embedding: [1, 0], category: "context", importance: 0.5)
        let engine = RecallEngine(vectorStoreFactory: factory)
        let results = await engine.recall(query: [1, 0], memories: [memory], limit: 5)
        XCTAssertEqual(results.count, 1, "VectorStore 空时应回退到暴力扫描，返回 1 条")
        XCTAssertEqual(results.first?.content, "测试")
    }

    /// 默认 limit 应为 5
    func testRecallDefaultLimit() async throws {
        XCTAssertEqual(RecallEngine.defaultResultLimit, 5, "默认 resultLimit 应为 5")
    }

    /// 候选数应为 20
    func testCandidateLimit() {
        XCTAssertEqual(RecallEngine.candidateLimit, 20, "candidateLimit 应为 20")
    }

    /// 权重常数应为 0.6 / 0.3 / 0.1
    func testWeightConstants() {
        XCTAssertEqual(RecallEngine.weightSimilarity, 0.6, accuracy: 0.0001)
        XCTAssertEqual(RecallEngine.weightImportance, 0.3, accuracy: 0.0001)
        XCTAssertEqual(RecallEngine.weightRecency, 0.1, accuracy: 0.0001)
        // 权重和应为 1.0
        let sum = RecallEngine.weightSimilarity + RecallEngine.weightImportance + RecallEngine.weightRecency
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001, "权重和应为 1.0")
    }

    /// 半衰期应为 30 天
    func testHalfLifeConstants() {
        XCTAssertEqual(RecallEngine.halfLifeSeconds, 30 * 24 * 60 * 60, "半衰期应为 30 天")
    }
}
