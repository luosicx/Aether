import XCTest
import SwiftData
@testable import Aether

/// Task 5: MemoryService 单元测试。
/// 使用 in-memory ModelContainer 与 StubEmbeddingService 注入，验证记忆的存储、语义检索、关键词搜索、删除与相似度计算。
@MainActor
final class MemoryServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var stub: StubEmbeddingService!
    private var service: MemoryService!

    override func setUpWithError() throws {
        // 隔离 Keychain：使用内存后端，避免依赖真实系统 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        // 写入 Qwen API Key，使 MemoryService 能进入 embedding 分支
        try KeychainManager.shared.saveAPIKey("test-key", for: .qwen)

        // in-memory ModelContainer，仅注册 Memory（测试不依赖其他模型）
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Memory.self, configurations: config)
        context = ModelContext(container)

        stub = StubEmbeddingService()
        service = MemoryService(modelContext: context, embeddingService: stub)
    }

    override func tearDownWithError() throws {
        service = nil
        stub = nil
        context = nil
        container = nil
        KeychainManager.shared.backend = SystemKeychainBackend()
    }

    // MARK: - 桩 EmbeddingService

    /// 桩子类：按文本查表返回预设向量；未配置的文本返回 defaultEmbedding。
    /// 用于 recall 测试中控制查询与记忆的相似度排序。
    final class StubEmbeddingService: EmbeddingService {
        var embeddingMap: [String: [Float]] = [:]
        var defaultEmbedding: [Float] = [0, 0, 0]

        override func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            return texts.map { embeddingMap[$0] ?? defaultEmbedding }
        }
    }

    // MARK: - Memory 初始化

    /// Memory 初始化应正确设置所有字段
    func testMemoryInitialization() {
        let conversationID = UUID()
        let memory = Memory(
            content: "测试记忆",
            embedding: [0.1, 0.2],
            category: "fact",
            importance: 0.8,
            sourceConversationID: conversationID
        )

        XCTAssertEqual(memory.content, "测试记忆")
        XCTAssertEqual(memory.embedding, [0.1, 0.2])
        XCTAssertEqual(memory.category, "fact")
        XCTAssertEqual(memory.importance, 0.8, accuracy: 0.001)
        XCTAssertEqual(memory.sourceConversationID, conversationID)
        XCTAssertNotNil(memory.id)
        XCTAssertLessThan(memory.createdAt.timeIntervalSinceNow, 1.0, "createdAt 应为当前时间附近")
    }

    /// Memory 默认值应正确
    func testMemoryDefaultValues() {
        let memory = Memory(content: "默认记忆")

        XCTAssertEqual(memory.embedding, [], "默认 embedding 应为空数组")
        XCTAssertEqual(memory.category, "context", "默认 category 应为 context")
        XCTAssertEqual(memory.importance, 0.5, accuracy: 0.001, "默认 importance 应为 0.5")
        XCTAssertNil(memory.sourceConversationID, "默认 sourceConversationID 应为 nil")
    }

    // MARK: - remember 存储记忆

    /// remember 应存储记忆并生成 embedding
    func testRememberStoresMemoryWithEmbedding() async throws {
        stub.embeddingMap["苹果"] = [1, 0, 0]

        let memory = try await service.remember(content: "苹果", category: "preference", importance: 0.9)

        XCTAssertEqual(memory.content, "苹果")
        XCTAssertEqual(memory.category, "preference")
        XCTAssertEqual(memory.importance, 0.9, accuracy: 0.001)
        XCTAssertEqual(memory.embedding, [1.0, 0.0, 0.0], "embedding 应由 stub 生成并转为 Double")

        // 应能从持久化层 fetch 到
        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 1, "存储后应有 1 条记忆")
        XCTAssertEqual(all.first?.content, "苹果")
    }

    /// remember 使用默认参数应正确
    func testRememberWithDefaults() async throws {
        let memory = try await service.remember(content: "默认内容")

        XCTAssertEqual(memory.category, "context")
        XCTAssertEqual(memory.importance, 0.5, accuracy: 0.001)
        XCTAssertNil(memory.sourceConversationID)
    }

    /// remember 带 sourceConversationID 应正确存储
    func testRememberWithSourceConversationID() async throws {
        let conversationID = UUID()
        let memory = try await service.remember(content: "来源记忆", sourceConversationID: conversationID)

        XCTAssertEqual(memory.sourceConversationID, conversationID)
    }

    // MARK: - recall 语义检索

    /// recall 应按余弦相似度降序返回记忆
    func testRecallReturnsBySimilarityOrder() async throws {
        // 配置 stub：两条记忆 + 查询向量
        stub.embeddingMap["我喜欢吃苹果"] = [1, 0, 0]
        stub.embeddingMap["今天天气很好"] = [0, 1, 0]
        stub.embeddingMap["苹果"] = [1, 0, 0]  // 查询向量，与记忆 A 同向

        _ = try await service.remember(content: "我喜欢吃苹果")
        _ = try await service.remember(content: "今天天气很好")

        let results = try await service.recall(query: "苹果", limit: 5)

        XCTAssertEqual(results.count, 2, "应返回 2 条记忆")
        XCTAssertEqual(results.first?.content, "我喜欢吃苹果", "与查询最相似的记忆应排首位")
        XCTAssertEqual(results.last?.content, "今天天气很好", "与查询正交的记忆应排末位")
    }

    /// recall limit 参数应限制返回条数
    func testRecallRespectsLimit() async throws {
        stub.embeddingMap["记忆1"] = [1, 0, 0]
        stub.embeddingMap["记忆2"] = [1, 0, 0]
        stub.embeddingMap["记忆3"] = [1, 0, 0]
        stub.embeddingMap["查询"] = [1, 0, 0]

        _ = try await service.remember(content: "记忆1")
        _ = try await service.remember(content: "记忆2")
        _ = try await service.remember(content: "记忆3")

        let results = try await service.recall(query: "查询", limit: 2)
        XCTAssertEqual(results.count, 2, "limit=2 应仅返回 2 条")
    }

    /// recall 无记忆时应返回空数组
    func testRecallEmptyReturnsEmpty() async throws {
        stub.embeddingMap["查询"] = [1, 0, 0]

        let results = try await service.recall(query: "查询")
        XCTAssertEqual(results, [], "无记忆时应返回空数组")
    }

    /// recall 仅返回有 embedding 的记忆（空 embedding 的记忆被跳过）
    func testRecallSkipsMemoriesWithoutEmbedding() async throws {
        // 直接插入一条无 embedding 的记忆（模拟 embedding 失败的降级存储）
        let noEmbedMemory = Memory(content: "无向量记忆", embedding: [], category: "context")
        context.insert(noEmbedMemory)
        try context.save()

        stub.embeddingMap["有向量记忆"] = [1, 0, 0]
        _ = try await service.remember(content: "有向量记忆")

        stub.embeddingMap["查询"] = [1, 0, 0]

        let results = try await service.recall(query: "查询", limit: 5)
        XCTAssertEqual(results.count, 1, "应仅返回有 embedding 的 1 条记忆")
        XCTAssertEqual(results.first?.content, "有向量记忆")
    }

    // MARK: - search 关键词搜索

    /// search 应按关键词大小写不敏感匹配 content
    func testSearchByKeyword() throws {
        // 直接插入记忆（不依赖 embedding）
        let m1 = Memory(content: "我喜欢吃苹果", category: "context")
        let m2 = Memory(content: "今天天气很好", category: "context")
        let m3 = Memory(content: "苹果手机很好用", category: "context")
        context.insert(m1)
        context.insert(m2)
        context.insert(m3)
        try context.save()

        let results = try service.search(keyword: "苹果")
        XCTAssertEqual(results.count, 2, "应匹配 2 条含「苹果」的记忆")
        XCTAssertTrue(results.contains { $0.content == "我喜欢吃苹果" })
        XCTAssertTrue(results.contains { $0.content == "苹果手机很好用" })
    }

    /// search 应大小写不敏感
    func testSearchCaseInsensitive() throws {
        let m = Memory(content: "I love Apple products", category: "fact")
        context.insert(m)
        try context.save()

        let results = try service.search(keyword: "apple")
        XCTAssertEqual(results.count, 1, "大小写不敏感应匹配 1 条")
        XCTAssertEqual(results.first?.content, "I love Apple products")
    }

    /// search limit 应限制返回条数
    func testSearchRespectsLimit() throws {
        for i in 0..<5 {
            let m = Memory(content: "测试记忆\(i)", category: "context")
            context.insert(m)
        }
        try context.save()

        let results = try service.search(keyword: "测试", limit: 3)
        XCTAssertEqual(results.count, 3, "limit=3 应仅返回 3 条")
    }

    /// search 无匹配时应返回空数组
    func testSearchNoMatchReturnsEmpty() throws {
        let m = Memory(content: "苹果", category: "context")
        context.insert(m)
        try context.save()

        let results = try service.search(keyword: "香蕉")
        XCTAssertEqual(results, [], "无匹配应返回空数组")
    }

    // MARK: - delete 删除记忆

    /// delete 应从持久化层删除记忆
    func testDeleteMemory() async throws {
        let memory = try await service.remember(content: "待删除记忆")
        XCTAssertEqual(try service.getAllMemories().count, 1)

        try await service.delete(memory: memory)

        XCTAssertEqual(try service.getAllMemories().count, 0, "删除后应为空")
    }

    /// delete 多条后剩余应正确
    func testDeleteOneOfMultiple() async throws {
        let m1 = try await service.remember(content: "记忆1")
        _ = try await service.remember(content: "记忆2")
        XCTAssertEqual(try service.getAllMemories().count, 2)

        try await service.delete(memory: m1)

        let remaining = try service.getAllMemories()
        XCTAssertEqual(remaining.count, 1, "删除 1 条后应剩 1 条")
        XCTAssertEqual(remaining.first?.content, "记忆2")
    }

    // MARK: - cosineSimilarity 计算

    /// 相同向量相似度应为 1.0
    func testCosineSimilarityIdenticalVectors() {
        let a = [1.0, 2.0, 3.0]
        let sim = service.cosineSimilarity(a, a)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "相同向量相似度应为 1.0")
    }

    /// 正交向量相似度应为 0
    func testCosineSimilarityOrthogonalVectors() {
        let a = [1.0, 0.0]
        let b = [0.0, 1.0]
        let sim = service.cosineSimilarity(a, b)
        XCTAssertEqual(sim, 0.0, accuracy: 0.0001, "正交向量相似度应为 0")
    }

    /// 长度不等的向量应返回 0
    func testCosineSimilarityDifferentLengths() {
        let a = [1.0, 2.0, 3.0]
        let b = [1.0, 2.0]
        let sim = service.cosineSimilarity(a, b)
        XCTAssertEqual(sim, 0.0, "长度不等的向量应返回 0")
    }

    /// 空向量应返回 0
    func testCosineSimilarityEmptyVectors() {
        XCTAssertEqual(service.cosineSimilarity([], []), 0.0, "空向量应返回 0")
        XCTAssertEqual(service.cosineSimilarity([1.0], []), 0.0, "一方为空应返回 0")
    }

    /// 零向量应返回 0（避免除零）
    func testCosineSimilarityZeroVectors() {
        let sim = service.cosineSimilarity([0.0, 0.0], [0.0, 0.0])
        XCTAssertEqual(sim, 0.0, "零向量应返回 0")
    }

    /// 同向不同幅度向量相似度应为 1.0
    func testCosineSimilaritySameDirection() {
        let a = [1.0, 0.0]
        let b = [5.0, 0.0]
        let sim = service.cosineSimilarity(a, b)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "同向向量相似度应为 1.0")
    }

    // MARK: - 按类别查询

    /// getByCategory 应仅返回指定类别的记忆
    func testGetByCategory() async throws {
        _ = try await service.remember(content: "偏好1", category: "preference")
        _ = try await service.remember(content: "事实1", category: "fact")
        _ = try await service.remember(content: "偏好2", category: "preference")
        _ = try await service.remember(content: "上下文1", category: "context")

        let preferences = try service.getByCategory("preference")
        XCTAssertEqual(preferences.count, 2, "preference 类别应有 2 条")
        XCTAssertTrue(preferences.allSatisfy { $0.category == "preference" })

        let facts = try service.getByCategory("fact")
        XCTAssertEqual(facts.count, 1, "fact 类别应有 1 条")
        XCTAssertEqual(facts.first?.content, "事实1")
    }

    /// getByCategory 无匹配类别时应返回空数组
    func testGetByCategoryNoMatch() async throws {
        _ = try await service.remember(content: "上下文", category: "context")

        let results = try service.getByCategory("instruction")
        XCTAssertEqual(results, [], "无 instruction 类别时应返回空数组")
    }

    // MARK: - getAllMemories

    /// getAllMemories 应返回所有记忆，按创建时间降序
    func testGetAllMemories() async throws {
        let m1 = try await service.remember(content: "第一条")
        // 确保时间差异（createdAt 同秒可能无法区分顺序）
        try? await Task.sleep(nanoseconds: 10_000_000)
        let m2 = try await service.remember(content: "第二条")

        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 2, "应返回 2 条记忆")
        // 降序：m2 在前
        XCTAssertEqual(all.first?.content, "第二条")
        XCTAssertEqual(all.last?.content, "第一条")
        _ = m1  // 避免未使用变量警告
    }

    /// getAllMemories 空仓库应返回空数组
    func testGetAllMemoriesEmpty() throws {
        XCTAssertEqual(try service.getAllMemories().count, 0, "空仓库应返回空数组")
    }

    // MARK: - 补充覆盖：无 API Key 降级与导入路径

    /// 无 Qwen Key 时 remember 仍应持久化记忆，但 embedding 为空数组（降级存储保证内容不丢失）
    func testRememberWithoutAPIKeyStoresWithEmptyEmbedding() async throws {
        // 重置 Keychain 后端，确保无 Qwen Key
        KeychainManager.shared.backend = InMemoryKeychainBackend()

        let memory = try await service.remember(content: "无 Key 记忆", category: "context", importance: 0.6)

        XCTAssertEqual(memory.embedding, [], "无 API Key 时 embedding 应为空数组")
        XCTAssertEqual(memory.content, "无 Key 记忆")
        XCTAssertEqual(memory.importance, 0.6, accuracy: 0.001, "无 Key 不影响 importance 透传")

        // 验证 Memory 已持久化到 SwiftData
        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 1, "记忆应已持久化")
        XCTAssertEqual(all.first?.content, "无 Key 记忆")
        XCTAssertEqual(all.first?.embedding, [], "持久化后的 embedding 应为空")
    }

    /// isUserExplicit=true 时即使传入 importance=0.3 也应被强制为 0.8（用户主动记忆默认重要）
    func testRememberUserExplicitForcesImportance08() async throws {
        let memory = try await service.remember(
            content: "用户主动记忆",
            importance: 0.3,
            isUserExplicit: true
        )

        XCTAssertEqual(memory.importance, 0.8, accuracy: 0.001, "isUserExplicit=true 应强制 importance=0.8")
        XCTAssertTrue(memory.isUserExplicit, "isUserExplicit 应保持为 true")

        // 持久化层应同步反映 importance=0.8
        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.importance, 0.8, accuracy: 0.001)
        XCTAssertTrue(all.first?.isUserExplicit ?? false)
    }

    /// 无 Qwen Key 时 recall 应直接返回空数组（不进入 embedding 路径）
    func testRecallWithoutAPIKeyReturnsEmpty() async throws {
        // 重置 Keychain，确保无 Qwen Key
        KeychainManager.shared.backend = InMemoryKeychainBackend()

        // 即使有带 embedding 的记忆存在，recall 也应返回空
        let existing = Memory(content: "已有记忆", embedding: [1.0, 0.0, 0.0], category: "context")
        context.insert(existing)
        try context.save()

        let results = try await service.recall(query: "任意查询", limit: 5)
        XCTAssertEqual(results, [], "无 API Key 时 recall 应返回空数组")
    }

    /// 无 Qwen Key 时 generateQueryEmbedding 应返回空数组（供 RecallEngine 复用的降级语义）
    func testGenerateQueryEmbeddingWithoutAPIKeyReturnsEmpty() async throws {
        // 重置 Keychain，确保无 Qwen Key
        KeychainManager.shared.backend = InMemoryKeychainBackend()

        let embedding = try await service.generateQueryEmbedding(for: "查询文本")
        XCTAssertEqual(embedding, [], "无 API Key 时 generateQueryEmbedding 应返回空数组")
    }

    /// insertImported 应保留传入 Memory 的原始 id 与 createdAt（用于跨设备恢复）
    func testInsertImportedPersistsMemory() throws {
        // 构造 Memory 并手动指定 id/createdAt（init 不接收这两个参数；与 ExportImporter 生产代码同模式）
        let customID = UUID()
        let customCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let memory = Memory(
            content: "导入记忆",
            embedding: [0.1, 0.2, 0.3],
            category: "fact",
            importance: 0.7,
            isUserExplicit: false
        )
        memory.id = customID
        memory.createdAt = customCreatedAt

        try service.insertImported(memory)

        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 1, "应已持久化 1 条记忆")
        XCTAssertEqual(all.first?.id, customID, "id 应保持指定原值，不被重新生成")
        XCTAssertEqual(all.first?.createdAt, customCreatedAt, "createdAt 应保持指定原值，不被覆盖为当前时间")
        XCTAssertEqual(all.first?.content, "导入记忆")
        XCTAssertEqual(all.first?.embedding, [0.1, 0.2, 0.3])
        XCTAssertEqual(all.first?.category, "fact")
        XCTAssertEqual(all.first?.importance, 0.7, accuracy: 0.001)
    }
}
