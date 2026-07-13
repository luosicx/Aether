import XCTest
import SwiftData
@testable import Aether

/// Task 8.3: SemanticMemoryStore 单元测试。
///
/// 覆盖范围：
/// - retrieveRelevantMemories 检索正确（委托 MemoryService.recall）
/// - formatMemoriesForPrompt 格式正确
/// - 空记忆处理
@MainActor
final class SemanticMemoryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var stub: StubEmbeddingService!
    private var memoryService: MemoryService!
    private var store: SemanticMemoryStore!

    override func setUpWithError() throws {
        // 隔离 Keychain：使用内存后端
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        // 写入 Qwen API Key，使 MemoryService 能进入 embedding 分支
        try KeychainManager.shared.saveAPIKey("test-key", for: .qwen)

        // in-memory ModelContainer，仅注册 Memory
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Memory.self, configurations: config)
        context = ModelContext(container)

        stub = StubEmbeddingService()
        memoryService = MemoryService(modelContext: context, embeddingService: stub)
        store = SemanticMemoryStore(memoryService: memoryService)
    }

    override func tearDownWithError() throws {
        store = nil
        memoryService = nil
        stub = nil
        context = nil
        container = nil
        KeychainManager.shared.backend = SystemKeychainBackend()
    }

    // MARK: - 桩 EmbeddingService

    /// 桩子类：按文本查表返回预设向量；未配置的文本返回 defaultEmbedding。
    final class StubEmbeddingService: EmbeddingService {
        var embeddingMap: [String: [Float]] = [:]
        var defaultEmbedding: [Float] = [0, 0, 0]

        override func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            return texts.map { embeddingMap[$0] ?? defaultEmbedding }
        }
    }

    // MARK: - retrieveRelevantMemories 检索

    /// 应按相似度降序返回相关记忆
    func testRetrieveRelevantMemoriesReturnsBySimilarity() async throws {
        stub.embeddingMap["我喜欢吃苹果"] = [1, 0, 0]
        stub.embeddingMap["今天天气很好"] = [0, 1, 0]
        stub.embeddingMap["苹果"] = [1, 0, 0]  // 查询向量，与记忆 A 同向

        _ = try await memoryService.remember(content: "我喜欢吃苹果", category: "preference")
        _ = try await memoryService.remember(content: "今天天气很好", category: "context")

        let memories = try await store.retrieveRelevantMemories(query: "苹果", limit: 3)

        XCTAssertEqual(memories.count, 2, "应返回 2 条记忆")
        XCTAssertEqual(memories.first?.content, "我喜欢吃苹果", "与查询最相似的记忆应排首位")
    }

    /// limit 参数应限制返回条数
    func testRetrieveRelevantMemoriesRespectsLimit() async throws {
        stub.embeddingMap["记忆1"] = [1, 0, 0]
        stub.embeddingMap["记忆2"] = [1, 0, 0]
        stub.embeddingMap["记忆3"] = [1, 0, 0]
        stub.embeddingMap["查询"] = [1, 0, 0]

        _ = try await memoryService.remember(content: "记忆1")
        _ = try await memoryService.remember(content: "记忆2")
        _ = try await memoryService.remember(content: "记忆3")

        let memories = try await store.retrieveRelevantMemories(query: "查询", limit: 2)
        XCTAssertEqual(memories.count, 2, "limit=2 应仅返回 2 条")
    }

    /// 默认 limit 应为 3
    func testRetrieveRelevantMemoriesDefaultLimit() async throws {
        stub.embeddingMap["查询"] = [1, 0, 0]

        // 存入 5 条记忆
        for i in 0..<5 {
            stub.embeddingMap["记忆\(i)"] = [1, 0, 0]
            _ = try await memoryService.remember(content: "记忆\(i)")
        }

        let memories = try await store.retrieveRelevantMemories(query: "查询")
        XCTAssertEqual(memories.count, 3, "默认 limit=3 应仅返回 3 条")
    }

    /// 无记忆时应返回空数组
    func testRetrieveRelevantMemoriesEmptyReturnsEmpty() async throws {
        stub.embeddingMap["查询"] = [1, 0, 0]

        let memories = try await store.retrieveRelevantMemories(query: "查询")
        XCTAssertEqual(memories, [], "无记忆时应返回空数组")
    }

    // MARK: - formatMemoriesForPrompt 格式

    /// 应按指定格式输出记忆文本
    func testFormatMemoriesForPromptFormat() {
        let m1 = Memory(content: "用户偏好简洁回答", category: "preference")
        let m2 = Memory(content: "用户是素食者", category: "fact")
        let m3 = Memory(content: "回答使用正式语气", category: "instruction")

        let text = store.formatMemoriesForPrompt([m1, m2, m3])

        let expected = """
        【相关记忆】
        1. [preference] 用户偏好简洁回答
        2. [fact] 用户是素食者
        3. [instruction] 回答使用正式语气
        """
        XCTAssertEqual(text, expected, "格式应与预期一致")
    }

    /// 单条记忆应正确格式化
    func testFormatMemoriesForPromptSingleMemory() {
        let memory = Memory(content: "用户喜欢深色模式", category: "preference")

        let text = store.formatMemoriesForPrompt([memory])

        let expected = """
        【相关记忆】
        1. [preference] 用户喜欢深色模式
        """
        XCTAssertEqual(text, expected)
    }

    /// 记忆顺序应保持传入顺序
    func testFormatMemoriesForPromptPreservesOrder() {
        let m1 = Memory(content: "第一条", category: "fact")
        let m2 = Memory(content: "第二条", category: "preference")

        let text = store.formatMemoriesForPrompt([m1, m2])
        XCTAssertTrue(text.contains("1. [fact] 第一条"), "第一条应在前面")
        XCTAssertTrue(text.contains("2. [preference] 第二条"), "第二条应在后面")
    }

    // MARK: - 空记忆处理

    /// 空记忆数组应返回空字符串
    func testFormatMemoriesForPromptEmptyReturnsEmpty() {
        let text = store.formatMemoriesForPrompt([])
        XCTAssertEqual(text, "", "空记忆数组应返回空字符串")
    }

    /// 端到端：检索后格式化（无记忆场景）
    func testRetrieveAndFormatEmptyMemories() async throws {
        stub.embeddingMap["查询"] = [1, 0, 0]

        let memories = try await store.retrieveRelevantMemories(query: "查询")
        let text = store.formatMemoriesForPrompt(memories)

        XCTAssertEqual(text, "", "无记忆时格式化文本应为空")
    }

    /// 端到端：检索后格式化（有记忆场景）
    func testRetrieveAndFormatWithMemories() async throws {
        stub.embeddingMap["用户偏好简洁回答"] = [1, 0, 0]
        stub.embeddingMap["简洁"] = [1, 0, 0]  // 查询向量与记忆同向

        _ = try await memoryService.remember(content: "用户偏好简洁回答", category: "preference")

        let memories = try await store.retrieveRelevantMemories(query: "简洁", limit: 3)
        let text = store.formatMemoriesForPrompt(memories)

        XCTAssertTrue(text.contains("【相关记忆】"), "格式化文本应含标题")
        XCTAssertTrue(text.contains("[preference] 用户偏好简洁回答"), "格式化文本应含记忆内容")
        XCTAssertTrue(text.contains("1."), "格式化文本应含序号")
    }
}
