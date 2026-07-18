import Foundation
import AetherFoundation
import AetherServices

/// Task 24: Aether SDK 统一入口。
///
/// 第三方集成 Aether 的对话/工具/RAG/embedding 能力的统一客户端。
/// 内部委托 `LLMProvider` 完成 LLM 调用，`SemanticCache` 完成语义缓存，
/// 通过 `AetherToolRegistry` 管理自定义工具。
///
/// `@unchecked Sendable`：内部所有可变状态由 NSLock 或 actor 保护。
public final class AetherClient: @unchecked Sendable {

    // MARK: - 配置与底层依赖

    /// SDK 配置（不可变）
    public let config: AetherConfig
    /// LLM Provider 实例（内部委托）
    private let provider: LLMProvider
    /// RAG 检索 provider（可选注入，App 层负责桥接 RAGService）
    private let ragProvider: AetherRAGProvider?
    /// Embedding provider（可选注入，默认复用 LLMProvider.embed）
    private let embeddingProvider: AetherEmbeddingProvider?
    /// 工具注册中心
    private let toolRegistry: AetherToolRegistry
    /// 语义缓存（懒加载，仅 cache.enabled 时创建；SemanticCache 是 @MainActor 隔离，故 cacheStorage 也通过 MainActor 访问）
    private var cacheStorage: SemanticCache?

    // MARK: - 初始化

    /// 创建 AetherClient
    /// - Parameter config: SDK 配置
    /// - Throws: 配置无效时抛 `AetherError.invalidConfig`
    public init(config: AetherConfig) throws {
        if let reason = config.validate() {
            throw AetherError.invalidConfig(reason: reason)
        }
        self.config = config
        self.provider = try AetherClient.resolveProvider(for: config)
        self.ragProvider = nil
        self.embeddingProvider = nil
        self.toolRegistry = AetherToolRegistry()
        self.cacheStorage = nil
    }

    /// 内部初始化器：允许注入 LLMProvider / RAGProvider / EmbeddingProvider（测试与 App 桥接用）
    /// - Parameters:
    ///   - config: SDK 配置
    ///   - provider: LLMProvider 实例
    ///   - ragProvider: RAG 检索 provider（可选）
    ///   - embeddingProvider: Embedding provider（可选，nil 时复用 provider.embed）
    ///   - toolRegistry: 工具注册中心（可选，nil 时创建空 registry）
    /// - Throws: 配置无效时抛 `AetherError.invalidConfig`
    public init(
        config: AetherConfig,
        provider: LLMProvider,
        ragProvider: AetherRAGProvider? = nil,
        embeddingProvider: AetherEmbeddingProvider? = nil,
        toolRegistry: AetherToolRegistry = AetherToolRegistry()
    ) throws {
        if let reason = config.validate() {
            throw AetherError.invalidConfig(reason: reason)
        }
        self.config = config
        self.provider = provider
        self.ragProvider = ragProvider
        self.embeddingProvider = embeddingProvider
        self.toolRegistry = toolRegistry
        self.cacheStorage = nil
    }

    // MARK: - 内部工具

    /// 解析 LLMProvider：onDevice 必须注入，其余通过 ModelProviderFactory 构造
    private static func resolveProvider(for config: AetherConfig) throws -> LLMProvider {
        switch config.provider {
        case .deepSeek, .qwen, .bff:
            return ModelProviderFactory.make(config.provider.internalProvider)
        case .onDevice:
            throw AetherError.invalidConfig(reason: "onDevice provider 必须通过 init(config:provider:) 注入 OfflineLLMProvider")
        }
    }

    /// 获取或懒创建 SemanticCache（@MainActor 隔离）
    /// - Returns: 缓存实例；若 cache 未启用返回 nil
    internal func getCache() async -> SemanticCache? {
        guard config.cache?.enabled == true else { return nil }
        // 所有 cacheStorage 访问均通过 MainActor 串行化（SemanticCache 本身是 @MainActor）
        return await MainActor.run {
            if self.cacheStorage == nil {
                self.cacheStorage = SemanticCache()
            }
            return self.cacheStorage
        }
    }

    // MARK: - Internal Accessors（供 API 扩展文件访问）

    internal var providerInternal: LLMProvider { provider }
    internal var ragProviderInternal: AetherRAGProvider? { ragProvider }
    internal var embeddingProviderInternal: AetherEmbeddingProvider? { embeddingProvider }
    internal var toolRegistryInternal: AetherToolRegistry { toolRegistry }
    internal var retryPolicyInternal: RetryPolicy { config.retryPolicy ?? .defaultPolicy }
}
