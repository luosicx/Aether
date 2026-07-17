import Foundation
import AetherFoundation

/// Task 24: Aether SDK 顶层配置结构。
///
/// 第三方调用方通过 `AetherConfig` 配置 LLM Provider、API Key、缓存、RAG、限流与鉴权。
/// 所有字段 `Sendable` 安全，可在 actor 间传递。
public struct AetherConfig: Sendable, Equatable {
    /// LLM 供应商
    public var provider: AetherProvider
    /// API Key（或 OAuth token，取决于 `auth` 方案）
    public var apiKey: String
    /// 自定义 BFF / Provider 基础 URL（可选，nil 时使用 Provider 默认）
    public var baseURL: URL?
    /// 语义缓存配置（nil 表示禁用缓存）
    public var cache: CacheConfig?
    /// RAG 知识库配置（nil 表示不启用 RAG）
    public var rag: RAGConfig?
    /// 限流配置（nil 表示使用 Provider 默认）
    public var rateLimit: RateLimitConfig?
    /// 鉴权方案
    public var auth: AuthConfig
    /// 重试策略（nil 表示使用默认策略）
    public var retryPolicy: RetryPolicy?

    /// 创建配置
    public init(
        provider: AetherProvider,
        apiKey: String,
        baseURL: URL? = nil,
        cache: CacheConfig? = nil,
        rag: RAGConfig? = nil,
        rateLimit: RateLimitConfig? = nil,
        auth: AuthConfig = .default,
        retryPolicy: RetryPolicy? = .default
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.cache = cache
        self.rag = rag
        self.rateLimit = rateLimit
        self.auth = auth
        self.retryPolicy = retryPolicy
    }

    /// 校验配置是否有效
    /// - Returns: nil 表示有效；否则返回错误原因
    public func validate() -> String? {
        // onDevice 不要求 apiKey，其余 provider 必须有 apiKey
        if provider != .onDevice && apiKey.isEmpty {
            return "apiKey 不能为空"
        }
        if let cache = cache, cache.similarityThreshold < 0 || cache.similarityThreshold > 1 {
            return "cache.similarityThreshold 必须在 [0, 1] 区间"
        }
        if let rag = rag, rag.topK <= 0 {
            return "rag.topK 必须 > 0"
        }
        if let rateLimit = rateLimit, rateLimit.qps <= 0 || rateLimit.maxConcurrent <= 0 {
            return "rateLimit.qps 与 rateLimit.maxConcurrent 必须 > 0"
        }
        return nil
    }
}

/// LLM 供应商枚举（SDK 公共版本，与内部 `ModelProvider` 解耦）
public enum AetherProvider: String, Sendable, CaseIterable, Equatable {
    case deepSeek
    case qwen
    case bff
    case onDevice

    /// 转换为内部 `ModelProvider`
    internal var internalProvider: ModelProvider {
        switch self {
        case .deepSeek: return .deepseek
        case .qwen: return .qwen
        case .bff: return .deepseek // BFF 走 DeepSeek 兼容路径，BFF 逻辑由 AuthConfig 体现
        case .onDevice: return .onDevice
        }
    }
}

/// 语义缓存配置
public struct CacheConfig: Sendable, Equatable {
    /// 是否启用缓存
    public var enabled: Bool
    /// 缓存 TTL（秒），默认 1 小时
    public var ttl: TimeInterval
    /// 余弦相似度阈值，默认 0.92
    public var similarityThreshold: Float
    /// 最大容量，默认 100
    public var maxCapacity: Int

    public init(
        enabled: Bool = true,
        ttl: TimeInterval = 3600,
        similarityThreshold: Float = 0.92,
        maxCapacity: Int = 100
    ) {
        self.enabled = enabled
        self.ttl = ttl
        self.similarityThreshold = similarityThreshold
        self.maxCapacity = maxCapacity
    }

    /// 默认配置
    public static let `default` = CacheConfig()
}

/// RAG 知识库配置
public struct RAGConfig: Sendable, Equatable {
    /// 知识库 ID（关联 App 端 SwiftData DocumentChunk.source）
    public var knowledgeBaseID: String
    /// 默认检索 top-K，默认 5
    public var topK: Int

    public init(knowledgeBaseID: String, topK: Int = 5) {
        self.knowledgeBaseID = knowledgeBaseID
        self.topK = topK
    }
}

/// 限流配置
public struct RateLimitConfig: Sendable, Equatable {
    /// 每秒查询数
    public var qps: Int
    /// 最大并发请求数
    public var maxConcurrent: Int

    public init(qps: Int = 10, maxConcurrent: Int = 4) {
        self.qps = qps
        self.maxConcurrent = maxConcurrent
    }

    /// 默认配置
    public static let `default` = RateLimitConfig()
}
