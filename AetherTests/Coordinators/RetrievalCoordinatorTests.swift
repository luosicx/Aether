import XCTest
import SwiftData
import AetherFoundation
import AetherServices
@testable import Aether

/// P2-6 Task 7: RetrievalCoordinator 单元测试
///
/// 验证 RetrievalCoordinator 正确封装 RAG 检索 + 语义缓存读写 + embedding 降级逻辑：
/// - RAG 检索（DeepSeek 降级到 Qwen / Qwen 直连 / DeepSeek 无 Qwen Key 设置错误 / 关闭清空 citations）
/// - 语义缓存命中 / 未命中
/// - 缓存写入守卫（工具模式不写入 / 空响应不写入 / 空 embedding 不写入）
/// - embedding 多向量取首个 / 空结果降级到空向量
/// - RAG embedding 降级（DeepSeek 无 Qwen Key 时 resolveEmbedding 返回 nil）
///
/// 通过闭包回调更新外部状态（currentCitations / errorMessage），不直接持有 @Observable 属性。
@MainActor
final class RetrievalCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
        // 隔离 Keychain：使用内存后端，避免依赖真实系统 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        // 恢复真实 Keychain 后端，避免影响其他测试类
        KeychainManager.shared.backend = SystemKeychainBackend()
    }

    // MARK: - 辅助

    /// RetrievalCoordinator 测试夹具：构造 coordinator 同时持有闭包回调写入的 Box，便于断言。
    /// 使用 struct 而非多元组返回，避免触发 SwiftLint large_tuple（warning 阈值 4）。
    private struct RetrievalFixture {
        let coordinator: RetrievalCoordinator
        let currentCitations: NonIsolatedBox<[DocumentChunk]>
        let errorMessage: NonIsolatedBox<String?>
        let selectedProvider: NonIsolatedBox<ModelProvider>
        let ragEnabled: NonIsolatedBox<Bool>
        let toolsEnabled: NonIsolatedBox<Bool>
    }

    /// 构造一个 RetrievalCoordinator 并捕获闭包回调值，便于断言。
    /// selectedProvider / ragEnabled / toolsEnabled 通过 NonIsolatedBox 持有以模拟 ChatViewModel 的 @Observable 属性。
    private func makeCoordinator(
        selectedProvider: ModelProvider = .deepseek,
        ragEnabled: Bool = false,
        toolsEnabled: Bool = false,
        cache: SemanticCache = SemanticCache(),
        ragService: RAGService? = nil
    ) -> RetrievalFixture {
        let selectedBox = NonIsolatedBox<ModelProvider>(selectedProvider)
        let ragEnabledBox = NonIsolatedBox<Bool>(ragEnabled)
        let toolsEnabledBox = NonIsolatedBox<Bool>(toolsEnabled)
        let citationsBox = NonIsolatedBox<[DocumentChunk]>([])
        let errorBox = NonIsolatedBox<String?>(nil)
        let coordinator = RetrievalCoordinator(
            cache: cache,
            selectedProviderProvider: { selectedBox.value },
            ragEnabledProvider: { ragEnabledBox.value },
            toolsEnabledProvider: { toolsEnabledBox.value },
            onCurrentCitationsChange: { citationsBox.value = $0 },
            onErrorMessageChange: { errorBox.value = $0 },
            ragService: ragService
        )
        return RetrievalFixture(
            coordinator: coordinator,
            currentCitations: citationsBox,
            errorMessage: errorBox,
            selectedProvider: selectedBox,
            ragEnabled: ragEnabledBox,
            toolsEnabled: toolsEnabledBox
        )
    }

    // MARK: - RAG 检索

    /// RAG 开启 + DeepSeek provider + 配置 Qwen Key 时应成功降级到 Qwen 进行 embedding。
    /// 验证 ragEmbeddingProvider 解析为 .qwen，handleRAGRetrieving 不设置 DeepSeek 不支持错误。
    func testRAGRetrievingDeepSeekEmbedsSuccessfully() async throws {
        try KeychainManager.shared.saveAPIKey("test-qwen-key", for: .qwen)
        // 注入 mock RAGService 避免真实网络调用（EmbeddingService 用 mock LLMProvider）
        let mock = MockLLMProvider()
        mock.embedResult = [[0.1, 0.2, 0.3]]
        let ragService = RAGService(embeddingService: EmbeddingService(client: mock))
        let fx = makeCoordinator(
            selectedProvider: .deepseek,
            ragEnabled: true,
            ragService: ragService
        )

        // DeepSeek + Qwen Key 应降级到 .qwen
        XCTAssertEqual(fx.coordinator.ragEmbeddingProvider, .qwen,
                       "DeepSeek + Qwen Key 时应降级到 .qwen 进行 embedding")

        let (ragContext, embedding) = await fx.coordinator.handleRAGRetrieving(
            text: "你好", modelContext: context, llmClient: mock, apiKey: ""
        )

        // 空 ModelContext 无文档分块，context 为空但 embedding 已计算
        XCTAssertTrue(ragContext.isEmpty, "无文档分块时 context 应为空")
        XCTAssertEqual(embedding, [0.1, 0.2, 0.3], "应返回 mock embedding（Qwen embedding 调用成功）")
        XCTAssertNil(fx.errorMessage.value, "Qwen Key 已配置且 embedding 成功时不应设置 errorMessage")
    }

    /// RAG 开启 + DeepSeek provider 无 Qwen Key 时应设置 embedding 不支持错误并清空 citations。
    func testRAGRetrievingDeepSeekNoQwenKeySetsEmbeddingError() async throws {
        // 不预置 Qwen Key（setUp 已用 InMemoryKeychainBackend 重置）
        let fx = makeCoordinator(
            selectedProvider: .deepseek,
            ragEnabled: true
        )

        XCTAssertEqual(fx.coordinator.ragEmbeddingProvider, .deepseek,
                       "DeepSeek 无 Qwen Key 时 ragEmbeddingProvider 应回退到 .deepseek")

        let (ragContext, embedding) = await fx.coordinator.handleRAGRetrieving(
            text: "你好", modelContext: context, llmClient: MockLLMProvider(), apiKey: ""
        )

        XCTAssertEqual(ragContext, "", "降级守卫触发时 context 应为空")
        XCTAssertTrue(embedding.isEmpty, "降级守卫触发时 embedding 应为空")
        XCTAssertEqual(
            fx.errorMessage.value,
            NSLocalizedString("DeepSeek 不支持知识库嵌入，请在设置中配置 Qwen API Key 或切换供应商为 Qwen", comment: ""),
            "应设置 embedding 不支持错误"
        )
        XCTAssertTrue(fx.currentCitations.value.isEmpty, "降级时应清空 currentCitations")
    }

    /// RAG 开启 + Qwen provider 时应尝试调用 Qwen embedding（ragEmbeddingProvider 应为 .qwen）。
    func testRAGRetrievingQwenProviderAttemptsEmbedding() async throws {
        try KeychainManager.shared.saveAPIKey("test-qwen-key", for: .qwen)
        // 注入 mock RAGService 避免真实网络调用
        let mock = MockLLMProvider()
        mock.embedResult = [[0.4, 0.5, 0.6]]
        let ragService = RAGService(embeddingService: EmbeddingService(client: mock))
        let fx = makeCoordinator(
            selectedProvider: .qwen,
            ragEnabled: true,
            ragService: ragService
        )

        XCTAssertEqual(fx.coordinator.ragEmbeddingProvider, .qwen,
                       "Qwen provider 时 ragEmbeddingProvider 应为 .qwen")

        let (ragContext, embedding) = await fx.coordinator.handleRAGRetrieving(
            text: "你好", modelContext: context, llmClient: mock, apiKey: ""
        )
        // 空 ModelContext 无文档分块，context 为空但 embedding 已计算（说明尝试了 Qwen embedding）
        XCTAssertTrue(ragContext.isEmpty, "无文档分块时 context 应为空")
        XCTAssertEqual(embedding, [0.4, 0.5, 0.6], "应返回 mock embedding（Qwen embedding 调用成功）")
    }

    /// RAG 关闭时应清空 currentCitations（即使预置了非空值）。
    func testRAGDisabledClearsCitations() async throws {
        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false
        )
        // 预置非空 citations
        fx.currentCitations.value = [DocumentChunk(content: "旧引用1"), DocumentChunk(content: "旧引用2")]

        let _ = await fx.coordinator.handleRAGRetrieving(
            text: "你好", modelContext: context, llmClient: MockLLMProvider(), apiKey: ""
        )

        XCTAssertTrue(fx.currentCitations.value.isEmpty, "RAG 关闭时 currentCitations 应被清空")
    }

    // MARK: - 缓存查询

    /// 缓存命中时 checkCache 应返回缓存的 response。
    func testCacheCheckingHitReturnsCachedResponse() {
        let cache = SemanticCache()
        let embedding: [Float] = [1.0, 0.0, 0.0]
        cache.set(query: "你好", embedding: embedding, response: "cached-reply")

        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false,
            toolsEnabled: false,
            cache: cache
        )

        let cached = fx.coordinator.checkCache(query: "你好", embedding: embedding)
        XCTAssertEqual(cached, "cached-reply", "缓存命中应返回缓存的 response")
    }

    /// 缓存未命中时 checkCache 应返回 nil，调用方应继续走 LLM。
    func testCacheCheckingMissProceedsToLLM() {
        let cache = SemanticCache()
        let embedding: [Float] = [1.0, 0.0, 0.0]
        // 不预置缓存条目

        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false,
            toolsEnabled: false,
            cache: cache
        )

        let cached = fx.coordinator.checkCache(query: "你好", embedding: embedding)
        XCTAssertNil(cached, "缓存未命中应返回 nil，调用方继续走 LLM")
    }

    // MARK: - 缓存写入守卫

    /// 工具模式启用时不写入缓存（避免工具调用中间结果污染缓存）。
    func testCacheNotWrittenWhenToolsEnabled() {
        let cache = SemanticCache()
        let embedding: [Float] = [0.5, 0.5, 0.0]
        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false,
            toolsEnabled: true,
            cache: cache
        )

        fx.coordinator.writeCache(query: "你好", embedding: embedding, response: "工具模式回复")

        let cached = cache.get(query: "你好", embedding: embedding)
        XCTAssertNil(cached, "工具模式启用时不应写入缓存")
    }

    /// 空响应不写入缓存（fullResponse 为空时跳过 cache.set）。
    func testCacheNotWrittenWhenResponseEmpty() {
        let cache = SemanticCache()
        let embedding: [Float] = [1.0, 0.0, 0.0]
        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false,
            toolsEnabled: false,
            cache: cache
        )

        fx.coordinator.writeCache(query: "你好", embedding: embedding, response: "")

        let cached = cache.get(query: "你好", embedding: embedding)
        XCTAssertNil(cached, "空响应不应写入缓存")
    }

    /// 空 queryEmbedding 不写入缓存。
    func testEmptyQueryEmbeddingDoesNotWriteCache() {
        let cache = SemanticCache()
        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false,
            toolsEnabled: false,
            cache: cache
        )

        fx.coordinator.writeCache(query: "你好", embedding: [], response: "回复")

        let cached = cache.get(query: "你好", embedding: [])
        XCTAssertNil(cached, "空 embedding 时不应写入缓存")
    }

    // MARK: - embedding 计算

    /// embedding 返回空向量（如 [[]]）时应降级为空 embedding，调用方继续走 LLM。
    func testEmptyEmbedResultFallsBackToLLM() async throws {
        let mock = MockLLMProvider()
        mock.embedResult = [[]]  // 空向量
        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false,
            toolsEnabled: false
        )

        let (ragContext, embedding) = await fx.coordinator.handleRAGRetrieving(
            text: "你好", modelContext: context, llmClient: mock, apiKey: ""
        )

        XCTAssertEqual(ragContext, "", "RAG 关闭时 context 应为空")
        XCTAssertTrue(embedding.isEmpty, "空 embed 结果应降级为空 embedding，调用方继续走 LLM")
    }

    /// embedding 返回多向量时应取第一个向量作为 queryEmbedding。
    func testEmbedMultipleVectorsUsesFirstEmbedding() async throws {
        let mock = MockLLMProvider()
        mock.embedResult = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
        let fx = makeCoordinator(
            selectedProvider: .onDevice,
            ragEnabled: false,
            toolsEnabled: false
        )

        let (ragContext, embedding) = await fx.coordinator.handleRAGRetrieving(
            text: "你好", modelContext: context, llmClient: mock, apiKey: ""
        )

        XCTAssertEqual(ragContext, "", "RAG 关闭时 context 应为空")
        XCTAssertEqual(embedding, [0.1, 0.2, 0.3],
                       "多向量时应取第一个向量作为 queryEmbedding")
    }

    // MARK: - RAG embedding 降级

    /// DeepSeek + 无 Qwen Key 时 resolveEmbedding 返回 nil，触发降级守卫。
    /// 复用 ChatViewModelTests.testRAGEmbeddingDegradationDeepSeekNoQwenKey 的核心断言。
    func testRAGEmbeddingDegradationDeepSeekNoQwenKey() {
        // 测试环境中 Keychain 无 Qwen Key（setUp 已重置）
        let resolved = EmbeddingService.resolveEmbedding(for: .deepseek)
        XCTAssertNil(resolved, "DeepSeek 无 Qwen Key 时 resolveEmbedding 应返回 nil（触发降级守卫）")

        // Qwen provider 应正常解析（不需要 Qwen Key 降级）
        let qwenResolved = EmbeddingService.resolveEmbedding(for: .qwen)
        XCTAssertNotNil(qwenResolved, "Qwen provider 应正常解析")
        XCTAssertEqual(qwenResolved?.1, .qwen, "Qwen provider 解析结果应为 .qwen")
    }
}
