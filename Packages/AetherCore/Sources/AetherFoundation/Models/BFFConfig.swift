import Foundation

/// Day 15: BFF 代理层配置。承载 BFF 网关的 endpoint、用户令牌与客户端限流参数。
/// Codable + Sendable：支持序列化到 UserDefaults 并跨 actor 传递。
///
/// P1-11 (H-S5): 增加 `tokenIssuedAt` 与 `tokenTTLSeconds`，使客户端持有的 BFF Token
/// 具备本地 TTL 检查能力。Token 一旦泄露，攻击者最多使用 90 天；过期后客户端拒绝发送
/// 请求并提示用户重新设置 Token。服务端 auth.js 也会校验 KV 记录中的 `expiresAt` 字段，
/// 形成双端协同的过期防线。
///
/// P1-12 (H-S1): 增加 `pinnedSPKIHashes`，支持 SSL Pinning（证书固定）。
/// 配置后 BFFProxyClient 会校验服务器证书链中叶子证书的 SPKI (Subject Public Key Info)
/// SHA256 hash 是否匹配预置 pin，防止 MITM 攻击（伪造 CA、企业代理拦截、根证书被攻破等）。
/// hash 格式为 Base64 编码的 SHA256 摘要（与 OkHttp / TrustKit 兼容）。
/// 默认空数组（不启用 Pinning，仅依赖系统证书链校验）；用户部署 BFF 后应计算并配置 pin。
public struct BFFConfig: Codable, Sendable, Equatable {
    /// 是否启用 BFF 代理（默认 false，启用后请求经服务端中转，API Key 不落设备）
    public var enabled: Bool = false
    /// BFF 网关 endpoint（默认占位地址，部署后替换为真实域名）
    public var endpointURL: URL? = URL(string: "https://aether-bff.example.com")
    /// 用户级 BFF Token（用于服务端鉴权，替代上游 API Key）
    public var userToken: String = ""
    /// Token 签发时间（首次设置或变更时记录；用于客户端 TTL 检查）
    public var tokenIssuedAt: Date?
    /// P1-12: SSL Pinning 预置的 SPKI SHA256 hash 列表（Base64 编码）
    /// 非空时 BFFProxyClient 启用证书固定校验；为空时仅依赖系统证书链校验。
    /// 支持配置多个 hash 以便证书轮换（主备 pin）。
    public var pinnedSPKIHashes: [String] = []
    /// chat 接口客户端限流（每分钟令牌数，默认 20）
    public var chatRateLimitPerMin: Int = 20
    /// embed 接口客户端限流（每分钟令牌数，默认 10）
    public var embedRateLimitPerMin: Int = 10

    /// 默认配置（未启用 BFF 时的兜底值）
    public static let `default` = BFFConfig()

    /// UserDefaults 缓存键（现仅用于存储非敏感字段）
    public static let userDefaultsKey = "bff_config_cache"
    /// Keychain account for user token
    public static let userTokenKeychainAccount = "com.aether.bff.userToken"

    /// P1-11: BFF Token 客户端 TTL（90 天 = 7,776,000 秒）
    /// 超过此时间客户端拒绝发送请求，提示用户重新设置 Token。
    /// 此 TTL 仅为客户端兜底（防泄露 token 永久有效），服务端 KV 中的 `expiresAt` 是真正的过期防线。
    public static let tokenTTLSeconds: TimeInterval = 90 * 24 * 60 * 60

    public init(
        enabled: Bool = false,
        endpointURL: URL? = URL(string: "https://aether-bff.example.com"),
        userToken: String = "",
        tokenIssuedAt: Date? = nil,
        pinnedSPKIHashes: [String] = [],
        chatRateLimitPerMin: Int = 20,
        embedRateLimitPerMin: Int = 10
    ) {
        self.enabled = enabled
        self.endpointURL = endpointURL
        self.userToken = userToken
        self.tokenIssuedAt = tokenIssuedAt
        self.pinnedSPKIHashes = pinnedSPKIHashes
        self.chatRateLimitPerMin = chatRateLimitPerMin
        self.embedRateLimitPerMin = embedRateLimitPerMin
    }

    /// P1-11: 客户端 TTL 检查——Token 是否已过期。
    /// - 无 Token 或无签发时间视为未过期（避免误报阻止合法请求）
    /// - 签发时间 + TTL < 当前时间视为过期
    public var isTokenExpired: Bool {
        guard !userToken.isEmpty, let issuedAt = tokenIssuedAt else {
            return false
        }
        return Date().timeIntervalSince(issuedAt) > Self.tokenTTLSeconds
    }

    /// P1-12: 是否启用 SSL Pinning
    public var isSSLPinningEnabled: Bool {
        !pinnedSPKIHashes.isEmpty
    }
}

// MARK: - 非敏感字段拆分与持久化辅助

public extension BFFConfig {
    /// 非敏感字段子集，单独持久化到 UserDefaults；不含 userToken。
    ///
    /// P1-11: 自定义 Codable 以支持向后兼容——旧版本 UserDefaults 中存储的 JSON
    /// 不含 `tokenIssuedAt` 字段，使用 decodeIfPresent 处理避免 DecodingError。
    ///
    /// P1-12: 增加 `pinnedSPKIHashes` 字段，同样使用 decodeIfPresent 向后兼容。
    struct NonSensitive: Codable, Sendable, Equatable {
        /// 是否启用 BFF 代理
        public var enabled: Bool = false
        /// BFF 网关 endpoint
        public var endpointURL: URL? = URL(string: "https://aether-bff.example.com")
        /// Token 签发时间（P1-11: 非敏感字段，可持久化到 UserDefaults）
        public var tokenIssuedAt: Date?
        /// P1-12: SSL Pinning 预置的 SPKI SHA256 hash 列表（Base64 编码，非敏感字段）
        public var pinnedSPKIHashes: [String] = []
        /// chat 接口客户端限流（每分钟令牌数）
        public var chatRateLimitPerMin: Int = 20
        /// embed 接口客户端限流（每分钟令牌数）
        public var embedRateLimitPerMin: Int = 10

        private enum CodingKeys: String, CodingKey {
            case enabled, endpointURL, tokenIssuedAt, pinnedSPKIHashes, chatRateLimitPerMin, embedRateLimitPerMin
        }

        public init(
            enabled: Bool = false,
            endpointURL: URL? = URL(string: "https://aether-bff.example.com"),
            tokenIssuedAt: Date? = nil,
            pinnedSPKIHashes: [String] = [],
            chatRateLimitPerMin: Int = 20,
            embedRateLimitPerMin: Int = 10
        ) {
            self.enabled = enabled
            self.endpointURL = endpointURL
            self.tokenIssuedAt = tokenIssuedAt
            self.pinnedSPKIHashes = pinnedSPKIHashes
            self.chatRateLimitPerMin = chatRateLimitPerMin
            self.embedRateLimitPerMin = embedRateLimitPerMin
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // enabled/endpointURL/chatRateLimitPerMin/embedRateLimitPerMin 强制要求（与旧版行为一致）
            self.enabled = try c.decode(Bool.self, forKey: .enabled)
            self.endpointURL = try c.decodeIfPresent(URL.self, forKey: .endpointURL)
                ?? URL(string: "https://aether-bff.example.com")
            // P1-11: tokenIssuedAt 使用 decodeIfPresent 向后兼容旧 JSON（缺失时为 nil）
            self.tokenIssuedAt = try c.decodeIfPresent(Date.self, forKey: .tokenIssuedAt)
            // P1-12: pinnedSPKIHashes 使用 decodeIfPresent 向后兼容旧 JSON（缺失时为空数组）
            self.pinnedSPKIHashes = try c.decodeIfPresent([String].self, forKey: .pinnedSPKIHashes) ?? []
            self.chatRateLimitPerMin = try c.decode(Int.self, forKey: .chatRateLimitPerMin)
            self.embedRateLimitPerMin = try c.decode(Int.self, forKey: .embedRateLimitPerMin)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(enabled, forKey: .enabled)
            try c.encodeIfPresent(endpointURL, forKey: .endpointURL)
            try c.encodeIfPresent(tokenIssuedAt, forKey: .tokenIssuedAt)
            try c.encode(pinnedSPKIHashes, forKey: .pinnedSPKIHashes)
            try c.encode(chatRateLimitPerMin, forKey: .chatRateLimitPerMin)
            try c.encode(embedRateLimitPerMin, forKey: .embedRateLimitPerMin)
        }
    }

    /// 提取非敏感字段子集
    var nonSensitive: NonSensitive {
        NonSensitive(
            enabled: enabled,
            endpointURL: endpointURL,
            tokenIssuedAt: tokenIssuedAt,
            pinnedSPKIHashes: pinnedSPKIHashes,
            chatRateLimitPerMin: chatRateLimitPerMin,
            embedRateLimitPerMin: embedRateLimitPerMin
        )
    }

    /// 用非敏感字段 + token 组装完整配置
    init(nonSensitive: NonSensitive, userToken: String) {
        self.enabled = nonSensitive.enabled
        self.endpointURL = nonSensitive.endpointURL
        self.userToken = userToken
        self.tokenIssuedAt = nonSensitive.tokenIssuedAt
        self.pinnedSPKIHashes = nonSensitive.pinnedSPKIHashes
        self.chatRateLimitPerMin = nonSensitive.chatRateLimitPerMin
        self.embedRateLimitPerMin = nonSensitive.embedRateLimitPerMin
    }
}
