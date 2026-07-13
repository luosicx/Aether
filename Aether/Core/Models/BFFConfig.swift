import Foundation

/// Day 15: BFF 代理层配置。承载 BFF 网关的 endpoint、用户令牌与客户端限流参数。
/// Codable + Sendable：支持序列化到 UserDefaults 并跨 actor 传递。
struct BFFConfig: Codable, Sendable, Equatable {
    /// 是否启用 BFF 代理（默认 false，启用后请求经服务端中转，API Key 不落设备）
    var enabled: Bool = false
    /// BFF 网关 endpoint（默认占位地址，部署后替换为真实域名）
    var endpointURL: URL? = URL(string: "https://aether-bff.example.com")
    /// 用户级 BFF Token（用于服务端鉴权，替代上游 API Key）
    var userToken: String = ""
    /// chat 接口客户端限流（每分钟令牌数，默认 20）
    var chatRateLimitPerMin: Int = 20
    /// embed 接口客户端限流（每分钟令牌数，默认 10）
    var embedRateLimitPerMin: Int = 10

    /// 默认配置（未启用 BFF 时的兜底值）
    static let `default` = BFFConfig()

    /// UserDefaults 缓存键（现仅用于存储非敏感字段）
    static let userDefaultsKey = "bff_config_cache"
    /// Keychain account for user token
    static let userTokenKeychainAccount = "com.aether.bff.userToken"
}

// MARK: - 非敏感字段拆分与持久化辅助

extension BFFConfig {
    /// 非敏感字段子集，单独持久化到 UserDefaults；不含 userToken。
    struct NonSensitive: Codable, Sendable, Equatable {
        /// 是否启用 BFF 代理
        var enabled: Bool = false
        /// BFF 网关 endpoint
        var endpointURL: URL? = URL(string: "https://aether-bff.example.com")
        /// chat 接口客户端限流（每分钟令牌数）
        var chatRateLimitPerMin: Int = 20
        /// embed 接口客户端限流（每分钟令牌数）
        var embedRateLimitPerMin: Int = 10
    }

    /// 提取非敏感字段子集
    var nonSensitive: NonSensitive {
        NonSensitive(
            enabled: enabled,
            endpointURL: endpointURL,
            chatRateLimitPerMin: chatRateLimitPerMin,
            embedRateLimitPerMin: embedRateLimitPerMin
        )
    }

    /// 用非敏感字段 + token 组装完整配置
    init(nonSensitive: NonSensitive, userToken: String) {
        self.enabled = nonSensitive.enabled
        self.endpointURL = nonSensitive.endpointURL
        self.userToken = userToken
        self.chatRateLimitPerMin = nonSensitive.chatRateLimitPerMin
        self.embedRateLimitPerMin = nonSensitive.embedRateLimitPerMin
    }
}
