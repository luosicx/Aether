import Foundation
import SwiftData
import AetherFoundation
import AetherServices
import os

/// P2-6 Task 7: RetrievalCoordinator —— RAG 检索 + 语义缓存 + embedding 降级协调器
///
/// 从 ChatViewModel 抽取的 Day 3/6 RAG 与缓存职责：
/// - `ragService` / `ragEmbeddingProvider` 改为存储属性（懒加载，按 selectedProvider 缓存，
///   provider 变化时自动失效重建，避免每次访问构造新实例，性能改进）
/// - `handleRAGRetrieving` RAG 检索 + embedding 降级（DeepSeek 无 Qwen Key 时设置错误并清空 citations）
/// - `checkCache` 语义缓存查询（仅非工具模式 + 非空 embedding 时查询）
/// - `writeCache` 语义缓存写入（仅非工具模式 + 非空响应 + 非空 embedding 时写入）
///
/// 通过闭包回调更新 ChatViewModel 的 @Observable 属性（currentCitations / errorMessage），
/// 不直接持有 @Observable 属性。
///
/// 并发边界：本类标注 `@MainActor`，所有方法与闭包在主 actor 上调用；
/// Keychain 读取通过 `Task.detached(priority: .userInitiated)` 跨 actor 调用避免阻塞主线程。
@MainActor
final class RetrievalCoordinator: Coordinator {
    // MARK: - State（由 coordinator 持有，外部通过 getter 读取）

    /// 注入的 RAGService（测试用，nil 时按 selectedProvider 懒加载）。
    /// 注入时直接使用，绕过缓存逻辑，便于测试隔离真实网络调用。
    private let injectedRagService: RAGService?

    /// 懒加载缓存的 RAGService（按 selectedProvider 缓存，provider 变化时自动失效重建）。
    /// 行为等价于 ChatViewModel 原始 `ragService` 计算属性，但避免每次访问构造新实例。
    private var cachedRagService: RAGService?
    /// 缓存 ragService 时对应的 selectedProvider（用于检测 provider 变化并失效缓存）。
    private var ragServiceProvider: ModelProvider?

    /// 懒加载缓存的 ragEmbeddingProvider（按 selectedProvider 缓存，provider 变化时自动失效重建）。
    /// 行为等价于 ChatViewModel 原始 `ragEmbeddingProvider` 计算属性，但避免重复调用 resolveEmbedding。
    private var cachedRagEmbeddingProvider: ModelProvider?
    /// 缓存 ragEmbeddingProvider 时对应的 selectedProvider（用于检测 provider 变化并失效缓存）。
    private var ragEmbeddingProviderKey: ModelProvider?

    // MARK: - Closure-based IO（与 ChatViewModel 双向通信）

    /// 语义缓存实例（由 ChatViewModel 持有并注入，checkCache / writeCache 操作同一实例）
    private let cache: SemanticCache
    /// 当前 selectedProvider 查询闭包（读取 ChatViewModel 的 @Observable var selectedProvider 当前值）
    /// 用于按需懒加载 ragService / ragEmbeddingProvider
    private let selectedProviderProvider: () -> ModelProvider
    /// ragEnabled 查询闭包（读取 ChatViewModel 的 @Observable var ragEnabled 当前值）
    private let ragEnabledProvider: () -> Bool
    /// toolsEnabled 查询闭包（读取 ChatViewModel 的 @Observable var toolsEnabled 当前值）
    /// 用于 checkCache / writeCache 守卫（工具模式不查不写缓存）
    private let toolsEnabledProvider: () -> Bool
    /// currentCitations 变更回调（ChatViewModel 设置，更新 @Observable var currentCitations）
    private let onCurrentCitationsChange: ([DocumentChunk]) -> Void
    /// errorMessage 变更回调（ChatViewModel 设置，更新 @Observable var errorMessage）
    private let onErrorMessageChange: (String?) -> Void

    /// 构造器
    /// - Parameters:
    ///   - cache: 语义缓存实例（由 ChatViewModel 持有并注入，checkCache / writeCache 操作同一实例）
    ///   - selectedProviderProvider: selectedProvider 当前值查询闭包（@MainActor）
    ///   - ragEnabledProvider: ragEnabled 当前值查询闭包（@MainActor）
    ///   - toolsEnabledProvider: toolsEnabled 当前值查询闭包（@MainActor）
    ///   - onCurrentCitationsChange: currentCitations 变更回调（@MainActor），同步到 ChatViewModel @Observable 属性
    ///   - onErrorMessageChange: errorMessage 变更回调（@MainActor），同步到 ChatViewModel @Observable 属性
    ///   - ragService: 注入的 RAGService（测试用，nil 时按 selectedProvider 懒加载）
    init(cache: SemanticCache,
         selectedProviderProvider: @escaping () -> ModelProvider,
         ragEnabledProvider: @escaping () -> Bool,
         toolsEnabledProvider: @escaping () -> Bool,
         onCurrentCitationsChange: @escaping ([DocumentChunk]) -> Void,
         onErrorMessageChange: @escaping (String?) -> Void,
         ragService: RAGService? = nil) {
        self.cache = cache
        self.selectedProviderProvider = selectedProviderProvider
        self.ragEnabledProvider = ragEnabledProvider
        self.toolsEnabledProvider = toolsEnabledProvider
        self.onCurrentCitationsChange = onCurrentCitationsChange
        self.onErrorMessageChange = onErrorMessageChange
        self.injectedRagService = ragService
    }

    /// RAG embedding 实际使用的供应商（DeepSeek 降级到 Qwen）。
    /// 首次访问或 selectedProvider 变化时调用 EmbeddingService.resolveEmbedding 计算，
    /// 后续直接返回缓存值，避免重复调用 resolveEmbedding。
    /// 行为等价于 ChatViewModel 原始 `ragEmbeddingProvider` 计算属性。
    var ragEmbeddingProvider: ModelProvider {
        let provider = selectedProviderProvider()
        // 命中缓存：provider 未变化时直接返回
        if let cached = cachedRagEmbeddingProvider, ragEmbeddingProviderKey == provider {
            return cached
        }
        // 未命中缓存或 provider 变化：重新计算并缓存
        let resolved = EmbeddingService.resolveEmbedding(for: provider)?.1 ?? provider
        cachedRagEmbeddingProvider = resolved
        ragEmbeddingProviderKey = provider
        return resolved
    }

    // MARK: - RAG 检索

    /// RAG 检索阶段——开启则调用 ragService.buildAugmentedContext 注入 systemPrompt；
    /// 关闭则按需计算 query embedding（仅非工具模式，缓存用）。
    /// 行为等价于 ChatViewModel 原始 `handleRAGRetrieving` 实现。
    ///
    /// - Day 6: 计算 query embedding（用于语义缓存查询/写入）
    ///   - RAG 开启时复用 RAG 的 query embedding，不重复调 embed API
    ///   - RAG 关闭但工具关闭时单独调一次 embed（缓存需要）
    ///   - 工具开启时不查缓存也不写缓存，但仍可复用 RAG embedding（无副作用）
    ///
    /// - Parameters:
    ///   - text: 用户输入文本
    ///   - modelContext: SwiftData 上下文（用于 RAG chunk 检索）
    ///   - llmClient: LLMProvider 实例（RAG 关闭时用于 query embedding 计算）
    ///   - apiKey: LLM API Key
    /// - Returns: (ragContext, queryEmbedding) 二元组
    ///   - ragContext: RAG 检索的增强上下文（无文档时为空字符串），调用方据此决定是否插入 system APIMessage
    ///   - queryEmbedding: query embedding（用于语义缓存查询/写入）
    func handleRAGRetrieving(text: String, modelContext: ModelContext, llmClient: LLMProvider, apiKey: String) async -> (String, [Float]) {
        if ragEnabledProvider() {
            // DeepSeek 不支持 embedding，未配置 Qwen Key 时降级失败，跳过 RAG 检索避免 404
            if ragEmbeddingProvider == .deepseek {
                onCurrentCitationsChange([])
                onErrorMessageChange(NSLocalizedString("DeepSeek 不支持知识库嵌入，请在设置中配置 Qwen API Key 或切换供应商为 Qwen", comment: ""))
                return ("", [])
            } else {
                do {
                    // RAG embedding 可能降级到 Qwen（DeepSeek 不支持 embedding），需用对应 provider 的 apiKey
                    let embProvider = ragEmbeddingProvider
                    let ragApiKey = await Task.detached(priority: .userInitiated) {
                        KeychainManager.shared.getAPIKey(for: embProvider) ?? ""
                    }.value
                    let resolved = resolveRagService()
                    let (context, citations, ragQueryEmbedding) = try await resolved.buildAugmentedContext(query: text, modelContext: modelContext, apiKey: ragApiKey)
                    if !context.isEmpty {
                        onCurrentCitationsChange(citations)
                    } else {
                        onCurrentCitationsChange([])
                    }
                    return (context, ragQueryEmbedding)
                } catch {
                    onCurrentCitationsChange([])
                    onErrorMessageChange(String(format: NSLocalizedString("知识库检索失败: %@", comment: ""), error.localizedDescription))
                    return ("", [])
                }
            }
        } else {
            onCurrentCitationsChange([])
            // 仅在非工具模式下需要 embedding（缓存用）；工具模式下不查不写缓存
            if !toolsEnabledProvider() {
                // P2-2: 将 try? 改为 do/catch + Logger.warning，便于诊断 embedding 失败原因
                let embeddings: [[Float]]
                do {
                    embeddings = try await llmClient.embed(texts: [text], apiKey: apiKey)
                } catch {
                    Logger.chat.warning("llmClient.embed 失败，已降级为空 embedding：\(error.localizedDescription, privacy: .public)")
                    embeddings = []
                }
                return ("", embeddings.first ?? [])
            }
            return ("", [])
        }
    }

    // MARK: - 语义缓存查询

    /// 查询语义缓存（仅非工具模式 + 非空 embedding 时查询）。
    /// 行为等价于 ChatViewModel 原始 `handleCacheChecking` 中 `cache.get` 调用及其前置守卫。
    /// - Parameters:
    ///   - query: 用户查询文本
    ///   - embedding: query embedding
    /// - Returns: 命中时返回缓存的 response；未命中或工具模式 / 空 embedding 时返回 nil
    func checkCache(query: String, embedding: [Float]) -> String? {
        // 仅非工具模式 + 非空 embedding 时查询
        guard !toolsEnabledProvider(), !embedding.isEmpty else { return nil }
        return cache.get(query: query, embedding: embedding)
    }

    // MARK: - 语义缓存写入

    /// 写入语义缓存（仅非工具模式 + 非空响应 + 非空 embedding 时写入）。
    /// 行为等价于 ChatViewModel 原始 `handleFinishing` 中 `cache.set` 调用及其前置守卫。
    /// - Parameters:
    ///   - query: 用户查询文本
    ///   - embedding: query embedding
    ///   - response: 完整 LLM 响应文本
    func writeCache(query: String, embedding: [Float], response: String) {
        // Day 6: 仅非工具模式且响应非空且 embedding 有效才写缓存，
        // 避免工具调用的中间结果污染缓存。
        guard !toolsEnabledProvider(), !response.isEmpty, !embedding.isEmpty else { return }
        cache.set(query: query, embedding: embedding, response: response)
    }

    // MARK: - 私有辅助

    /// 按 selectedProvider 构造或复用 RAGService（DeepSeek 降级到 Qwen）。
    /// - 注入 ragService 时直接返回（测试路径）。
    /// - 否则按 selectedProvider 缓存：provider 未变化时复用缓存，变化时重建。
    /// 行为等价于 ChatViewModel 原始 `ragService` 计算属性，但避免每次访问构造新实例。
    private func resolveRagService() -> RAGService {
        // 测试路径：注入了 ragService 时直接返回
        if let injected = injectedRagService {
            return injected
        }
        // 生产路径：按 selectedProvider 缓存
        let provider = selectedProviderProvider()
        if let cached = cachedRagService, ragServiceProvider == provider {
            return cached
        }
        let resolved = EmbeddingService.resolveEmbedding(for: provider)
            ?? (DeepSeekClient(), provider)
        let service = RAGService(embeddingService: EmbeddingService(client: resolved.0))
        cachedRagService = service
        ragServiceProvider = provider
        return service
    }
}
