import Foundation

/// Day 14: 远程配置数据模型。承载 App 启动时拉取的默认 System Prompt、默认 provider/model、功能开关等。
/// 远程配置仅作为「初始默认值」生效，不覆盖用户已自定义的本地配置。
struct RemoteConfig: Codable, Sendable, Equatable {
    /// 默认 System Prompt（用户未自定义时生效）
    var defaultSystemPrompt: String
    /// 默认 provider，值为 "deepseek" / "qwen"
    var defaultProvider: String
    /// 默认模型名
    var defaultModel: String
    /// 功能开关集合
    var featureFlags: FeatureFlags
    /// 维护模式开关，true 时 App 应展示维护提示
    var maintenanceMode: Bool
    /// 强制更新最低版本号，nil 表示不强制；非 nil 时低于该版本应阻断使用
    var forceUpdateMinVersion: String?
    /// 远程配置版本号，用于判断是否需要刷新
    var configVersion: Int
    /// 本地缓存时间戳，记录最近一次拉取成功的时间，用于 TTL 判断
    var fetchedAt: Date?

    /// 功能开关：控制 RAG / 工具调用 / 自动降级等特性的全局启用状态
    struct FeatureFlags: Codable, Sendable, Equatable {
        /// RAG 知识库检索是否启用
        var ragEnabled: Bool
        /// 工具调用是否启用
        var toolsEnabled: Bool
        /// 自动降级（FallbackLLMProvider）是否启用
        var enableFallback: Bool

        /// 内置默认功能开关
        static let `default` = FeatureFlags(
            ragEnabled: false,
            toolsEnabled: true,
            enableFallback: false
        )

        /// 成员逐一初始化器（自定义 init(from:) 会抑制合成 init，需显式提供）
        init(ragEnabled: Bool = false, toolsEnabled: Bool = true, enableFallback: Bool = false) {
            self.ragEnabled = ragEnabled
            self.toolsEnabled = toolsEnabled
            self.enableFallback = enableFallback
        }

        /// 自定义解码：远程 JSON 缺失字段时使用内置默认值，避免因字段不全导致解码失败
        init(from decoder: Decoder) throws {
            let defaults = FeatureFlags.default
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 字段缺失时回退到默认值，保证远程配置向下兼容
            ragEnabled = try c.decodeIfPresent(Bool.self, forKey: .ragEnabled) ?? defaults.ragEnabled
            toolsEnabled = try c.decodeIfPresent(Bool.self, forKey: .toolsEnabled) ?? defaults.toolsEnabled
            enableFallback = try c.decodeIfPresent(Bool.self, forKey: .enableFallback) ?? defaults.enableFallback
        }
    }

    /// 自定义解码：远程 JSON 缺失字段时使用内置默认值，保证配置向下兼容
    init(from decoder: Decoder) throws {
        let defaults = RemoteConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 非可选字段缺失时回退到默认值
        defaultSystemPrompt = try c.decodeIfPresent(String.self, forKey: .defaultSystemPrompt) ?? defaults.defaultSystemPrompt
        defaultProvider = try c.decodeIfPresent(String.self, forKey: .defaultProvider) ?? defaults.defaultProvider
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? defaults.defaultModel
        featureFlags = try c.decodeIfPresent(FeatureFlags.self, forKey: .featureFlags) ?? defaults.featureFlags
        maintenanceMode = try c.decodeIfPresent(Bool.self, forKey: .maintenanceMode) ?? defaults.maintenanceMode
        forceUpdateMinVersion = try c.decodeIfPresent(String.self, forKey: .forceUpdateMinVersion)
        configVersion = try c.decodeIfPresent(Int.self, forKey: .configVersion) ?? defaults.configVersion
        // fetchedAt 仅本地缓存写入，远程 JSON 不含此字段，解码为 nil
        fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt)
    }

    /// 成员逐一初始化器，供本地构造与测试使用
    init(
        defaultSystemPrompt: String = "你是一个有帮助的AI助手。",
        defaultProvider: String = "deepseek",
        defaultModel: String = "deepseek-chat",
        featureFlags: FeatureFlags = .default,
        maintenanceMode: Bool = false,
        forceUpdateMinVersion: String? = nil,
        configVersion: Int = 1,
        fetchedAt: Date? = nil
    ) {
        self.defaultSystemPrompt = defaultSystemPrompt
        self.defaultProvider = defaultProvider
        self.defaultModel = defaultModel
        self.featureFlags = featureFlags
        self.maintenanceMode = maintenanceMode
        self.forceUpdateMinVersion = forceUpdateMinVersion
        self.configVersion = configVersion
        self.fetchedAt = fetchedAt
    }

    /// 内置默认配置，作为远程拉取失败且无本地缓存时的兜底
    static let `default` = RemoteConfig(
        defaultSystemPrompt: "你是一个有帮助的AI助手。",
        defaultProvider: "deepseek",
        defaultModel: "deepseek-chat",
        featureFlags: .default,
        maintenanceMode: false,
        forceUpdateMinVersion: nil,
        configVersion: 1,
        fetchedAt: nil
    )
}
