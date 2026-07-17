import XCTest
import SwiftData
@testable import Aether

/// Task 19 阶段 3: AgingCompactor 单元测试。
///
/// 覆盖：老化（90 天衰减 0.8）、归档（180 天 + importance<0.2）、压缩（同 category 相似度>0.92 合并）、
/// 30 天恢复窗口、用户主动记忆不参与老化/归档、周期统计。
@MainActor
final class AgingCompactorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var stub: StubEmbeddingService!
    private var service: MemoryService!
    private var factory: VectorStoreFactory!
    private var compactor: AgingCompactor!

    override func setUpWithError() throws {
        // 隔离 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        try KeychainManager.shared.saveAPIKey("test-key", for: .qwen)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Memory.self, configurations: config)
        context = ModelContext(container)

        stub = StubEmbeddingService()
        factory = VectorStoreFactory()
        factory.reset()
        // 注入 BruteForceVectorStore 保证测试一致性
        factory.setOverride(BruteForceVectorStore())

        service = MemoryService(modelContext: context, embeddingService: stub, vectorStoreFactory: factory)
        compactor = AgingCompactor(memoryService: service, vectorStoreFactory: factory)
    }

    override func tearDownWithError() throws {
        compactor.cancelScheduling()
        factory.reset()
        service = nil
        stub = nil
        context = nil
        container = nil
        KeychainManager.shared.backend = SystemKeychainBackend()
    }

    // MARK: - 桩 EmbeddingService

    final class StubEmbeddingService: EmbeddingService {
        var embeddingMap: [String: [Float]] = [:]
        var defaultEmbedding: [Float] = [0, 0, 0]

        override func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            return texts.map { embeddingMap[$0] ?? defaultEmbedding }
        }
    }

    // MARK: - 辅助

    /// 创建一条 Memory，手动设置 createdAt 与 lastAccessedAt
    private func makeMemory(
        content: String,
        embedding: [Double] = [1, 0],
        category: String = "context",
        importance: Double = 0.5,
        createdAt: Date,
        lastAccessedAt: Date? = nil,
        isUserExplicit: Bool = false
    ) -> Memory {
        let memory = Memory(
            content: content,
            embedding: embedding,
            category: category,
            importance: importance,
            isUserExplicit: isUserExplicit
        )
        // Memory.init 中 createdAt = Date()，无法注入；通过 KVC 或反射不可行，改为通过 SwiftData 的 modelContext.save 后直接修改 createdAt
        // SwiftData @Model 允许直接赋值
        memory.createdAt = createdAt
        if let last = lastAccessedAt {
            memory.lastAccessedAt = last
        }
        context.insert(memory)
        try? context.save()
        return memory
    }

    // MARK: - 老化规则

    /// 90 天未命中的记忆 importance 应 *= 0.8
    func testAgingDecaysOldMemories() throws {
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 天前
        let memory = makeMemory(content: "老记忆", importance: 0.5, createdAt: oldDate, lastAccessedAt: oldDate)

        let count = try compactor.applyAging()

        XCTAssertEqual(count, 1, "应老化 1 条")
        XCTAssertEqual(memory.importance, 0.4, accuracy: 0.001, "0.5 × 0.8 = 0.4")
    }

    /// 90 天内访问的记忆不应被老化
    func testAgingSkipsRecentlyAccessed() throws {
        let recent = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 天前
        let memory = makeMemory(content: "新记忆", importance: 0.5, createdAt: recent, lastAccessedAt: recent)

        let count = try compactor.applyAging()

        XCTAssertEqual(count, 0, "近期访问的记忆不应老化")
        XCTAssertEqual(memory.importance, 0.5, accuracy: 0.001, "importance 不变")
    }

    /// 用户主动记忆不参与老化
    func testAgingSkipsUserExplicit() throws {
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60)
        let memory = makeMemory(content: "用户主动", importance: 0.8, createdAt: oldDate, lastAccessedAt: oldDate, isUserExplicit: true)

        let count = try compactor.applyAging()

        XCTAssertEqual(count, 0, "用户主动记忆不老化")
        XCTAssertEqual(memory.importance, 0.8, accuracy: 0.001, "importance 不变")
    }

    /// 已归档记忆不参与老化
    func testAgingSkipsArchived() throws {
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60)
        let memory = makeMemory(content: "已归档", importance: 0.5, createdAt: oldDate, lastAccessedAt: oldDate)
        memory.archivedAt = Date()

        let count = try compactor.applyAging()

        XCTAssertEqual(count, 0, "已归档记忆不老化")
        XCTAssertEqual(memory.importance, 0.5, accuracy: 0.001)
    }

    // MARK: - 归档规则

    /// 180 天且 importance < 0.2 的记忆应归档
    func testArchiveAppliesToOldAndLowImportance() async throws {
        let oldDate = Date().addingTimeInterval(-200 * 24 * 60 * 60) // 200 天前
        let memory = makeMemory(content: "老旧低价值", importance: 0.1, createdAt: oldDate, lastAccessedAt: oldDate)

        let count = try await compactor.applyArchival()

        XCTAssertEqual(count, 1, "应归档 1 条")
        XCTAssertNotNil(memory.archivedAt, "archivedAt 应被设置")
    }

    /// 180 天但 importance ≥ 0.2 的记忆不归档
    func testArchiveSkipsHighImportance() async throws {
        let oldDate = Date().addingTimeInterval(-200 * 24 * 60 * 60)
        let memory = makeMemory(content: "老旧高价值", importance: 0.5, createdAt: oldDate, lastAccessedAt: oldDate)

        let count = try await compactor.applyArchival()

        XCTAssertEqual(count, 0, "importance ≥ 0.2 不应归档")
        XCTAssertNil(memory.archivedAt)
    }

    /// 180 天内的记忆不归档（即使 importance 低）
    func testArchiveSkipsRecentMemories() async throws {
        let recent = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let memory = makeMemory(content: "近期低价值", importance: 0.1, createdAt: recent, lastAccessedAt: recent)

        let count = try await compactor.applyArchival()

        XCTAssertEqual(count, 0, "近期记忆不归档")
        XCTAssertNil(memory.archivedAt)
    }

    /// 用户主动记忆不归档
    func testArchiveSkipsUserExplicit() async throws {
        let oldDate = Date().addingTimeInterval(-200 * 24 * 60 * 60)
        let memory = makeMemory(content: "用户主动", importance: 0.1, createdAt: oldDate, lastAccessedAt: oldDate, isUserExplicit: true)

        let count = try await compactor.applyArchival()

        XCTAssertEqual(count, 0, "用户主动记忆不归档")
        XCTAssertNil(memory.archivedAt)
    }

    /// 已归档记忆不重复归档
    func testArchiveSkipsAlreadyArchived() async throws {
        let oldDate = Date().addingTimeInterval(-200 * 24 * 60 * 60)
        let memory = makeMemory(content: "已归档", importance: 0.1, createdAt: oldDate, lastAccessedAt: oldDate)
        memory.archivedAt = Date()

        let count = try await compactor.applyArchival()

        XCTAssertEqual(count, 0, "已归档记忆不重复归档")
    }

    // MARK: - 压缩规则

    /// 同 category 相似度 > 0.92 应压缩（保留 importance 高的）
    func testCompressionMergesDuplicates() throws {
        let now = Date()
        // 两条相同向量的记忆，A 的 importance 更高
        let memoryA = makeMemory(content: "A", embedding: [1, 0], category: "preference", importance: 0.9, createdAt: now)
        let memoryB = makeMemory(content: "B", embedding: [1, 0], category: "preference", importance: 0.5, createdAt: now)

        let count = try compactor.applyCompression()

        XCTAssertEqual(count, 1, "应压缩 1 条")
        XCTAssertNil(memoryA.archivedAt, "importance 高的 A 应保留")
        XCTAssertNotNil(memoryB.archivedAt, "importance 低的 B 应归档")
    }

    /// 不同 category 的记忆不压缩
    func testCompressionRespectsCategoryBoundary() throws {
        let now = Date()
        // 相同向量但不同 category
        _ = makeMemory(content: "A", embedding: [1, 0], category: "preference", importance: 0.9, createdAt: now)
        _ = makeMemory(content: "B", embedding: [1, 0], category: "fact", importance: 0.5, createdAt: now)

        let count = try compactor.applyCompression()

        XCTAssertEqual(count, 0, "不同 category 不压缩")
    }

    /// 相似度 ≤ 0.92 不压缩
    func testCompressionRespectsSimilarityThreshold() throws {
        let now = Date()
        // 余弦相似度 = 0.9（不超过 0.92）
        _ = makeMemory(content: "A", embedding: [1, 0], category: "context", importance: 0.9, createdAt: now)
        _ = makeMemory(content: "B", embedding: [0.9, 0.43589], category: "context", importance: 0.5, createdAt: now)

        let count = try compactor.applyCompression()

        XCTAssertEqual(count, 0, "相似度 ≤ 0.92 不压缩")
    }

    // MARK: - 恢复

    /// 30 天内归档的记忆可恢复
    func testRestoreWithinWindow() async throws {
        let now = Date()
        let memory = Memory(content: "归档", embedding: [1, 0], category: "context", importance: 0.1)
        context.insert(memory)
        try context.save()
        // 模拟 10 天前归档
        memory.archivedAt = now.addingTimeInterval(-10 * 24 * 60 * 60)

        let result = try await compactor.restore(memory: memory, now: now)

        XCTAssertTrue(result, "10 天内应可恢复")
        XCTAssertNil(memory.archivedAt, "恢复后 archivedAt 应清除")
    }

    /// 超出 30 天不可恢复
    func testRestoreOutsideWindowFails() async throws {
        let now = Date()
        let memory = Memory(content: "归档", embedding: [1, 0], category: "context", importance: 0.1)
        context.insert(memory)
        try context.save()
        // 50 天前归档（超 30 天窗口）
        memory.archivedAt = now.addingTimeInterval(-50 * 24 * 60 * 60)

        let result = try await compactor.restore(memory: memory, now: now)

        XCTAssertFalse(result, "超 30 天不应恢复")
        XCTAssertNotNil(memory.archivedAt, "archivedAt 应保持")
    }

    /// 未归档记忆调用 restore 返回 false
    func testRestoreOnActiveMemoryReturnsFalse() async throws {
        let memory = Memory(content: "活跃", embedding: [1, 0], category: "context", importance: 0.5)
        context.insert(memory)
        try context.save()

        let result = try await compactor.restore(memory: memory, now: Date())

        XCTAssertFalse(result, "活跃记忆 restore 应返回 false")
    }

    // MARK: - 完整周期

    /// runCycle 应执行老化、归档、压缩三步并返回统计
    func testRunCycleReturnsStatistics() async throws {
        let now = Date()
        // 老化候选：90+ 天未访问
        _ = makeMemory(content: "老化候选", importance: 0.5, createdAt: now.addingTimeInterval(-100 * 24 * 60 * 60))
        // 归档候选：200 天 + importance 0.1
        _ = makeMemory(content: "归档候选", importance: 0.1, createdAt: now.addingTimeInterval(-200 * 24 * 60 * 60))
        // 压缩候选：两条同 category 相同向量
        _ = makeMemory(content: "压缩A", embedding: [1, 0], category: "preference", importance: 0.9, createdAt: now)
        _ = makeMemory(content: "压缩B", embedding: [1, 0], category: "preference", importance: 0.5, createdAt: now)

        let result = try await compactor.runCycle(now: now)

        XCTAssertGreaterThanOrEqual(result.agedCount, 1, "至少老化 1 条")
        XCTAssertGreaterThanOrEqual(result.archivedCount, 1, "至少归档 1 条")
        XCTAssertGreaterThanOrEqual(result.compressedCount, 1, "至少压缩 1 条")
        XCTAssertEqual(result.runAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001, "runAt 应为传入的 now")
    }

    // MARK: - 常数

    /// 常数正确性检查
    func testConstants() {
        XCTAssertEqual(AgingCompactor.agingThresholdSeconds, 90 * 24 * 60 * 60)
        XCTAssertEqual(AgingCompactor.archiveAgeThresholdSeconds, 180 * 24 * 60 * 60)
        XCTAssertEqual(AgingCompactor.archiveImportanceThreshold, 0.2)
        XCTAssertEqual(AgingCompactor.agingDecayFactor, 0.8)
        XCTAssertEqual(AgingCompactor.compressionSimilarityThreshold, 0.92)
        XCTAssertEqual(AgingCompactor.restoreWindowSeconds, 30 * 24 * 60 * 60)
    }
}
