import Foundation

/// 插件清单，描述插件的元信息、工具定义与权限声明。
///
/// `parameters` 字段为 JSON Schema 字典（`[String: Any]`），不直接 Codable，
/// 因此对 `PluginToolDef` 实现自定义编解码：编码时用 JSONSerialization 转为 Data，
/// 解码时反向还原。Hashable 同理基于 Data 的稳定哈希。
public struct PluginManifest: Codable, Identifiable, Hashable {
    /// 插件唯一标识（UUID 字符串）
    public let id: String
    /// 插件名称
    public var name: String
    /// 插件版本号
    public var version: String
    /// 插件作者
    public var author: String
    /// 插件描述
    public var description: String
    /// 插件提供的工具定义列表
    public var tools: [PluginToolDef]
    /// 插件声明的权限列表
    public var permissions: [PluginPermission]
    /// 入口点（JS 脚本路径或 URL）
    public var entryPoint: String
    /// 依赖的其他插件 ID
    public var dependencies: [String]
    /// 生命周期钩子
    public var hooks: [PluginHook]
    /// 下载地址
    public var downloadURL: URL?
    /// Ed25519 签名
    public var signature: String?
    /// 最低 App 版本要求
    public var minAppVersion: String?

    /// PluginManifest 默认解码时使用的 CodingKeys
    enum CodingKeys: String, CodingKey {
        case id, name, version, author, description
        case tools, permissions, entryPoint
        case dependencies, hooks, downloadURL, signature, minAppVersion
    }

    public init(
        id: String,
        name: String,
        version: String,
        author: String,
        description: String,
        tools: [PluginToolDef],
        permissions: [PluginPermission],
        entryPoint: String,
        dependencies: [String] = [],
        hooks: [PluginHook] = [],
        downloadURL: URL? = nil,
        signature: String? = nil,
        minAppVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.tools = tools
        self.permissions = permissions
        self.entryPoint = entryPoint
        self.dependencies = dependencies
        self.hooks = hooks
        self.downloadURL = downloadURL
        self.signature = signature
        self.minAppVersion = minAppVersion
    }

    /// 自定义解码：兼容旧版本 manifest（缺失新字段时使用默认值）
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        author = try container.decode(String.self, forKey: .author)
        description = try container.decode(String.self, forKey: .description)
        tools = try container.decode([PluginToolDef].self, forKey: .tools)
        permissions = try container.decode([PluginPermission].self, forKey: .permissions)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
        // 新字段：缺失时回退默认值，保证向后兼容
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        hooks = try container.decodeIfPresent([PluginHook].self, forKey: .hooks) ?? []
        downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
        signature = try container.decodeIfPresent(String.self, forKey: .signature)
        minAppVersion = try container.decodeIfPresent(String.self, forKey: .minAppVersion)
    }

    /// 自定义编码：仅编码非 nil 字段（downloadURL / signature / minAppVersion 可选）
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(author, forKey: .author)
        try container.encode(description, forKey: .description)
        try container.encode(tools, forKey: .tools)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(entryPoint, forKey: .entryPoint)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(hooks, forKey: .hooks)
        try container.encodeIfPresent(downloadURL, forKey: .downloadURL)
        try container.encodeIfPresent(signature, forKey: .signature)
        try container.encodeIfPresent(minAppVersion, forKey: .minAppVersion)
    }

    /// 插件工具定义：名称、描述、JSON Schema 参数
    public struct PluginToolDef: Codable, Hashable {
        /// 工具名称
        public let name: String
        /// 工具描述
        public let description: String
        /// JSON Schema 参数字典
        public let parameters: [String: Any]

        // MARK: - Codable

        enum CodingKeys: String, CodingKey {
            case name, description, parameters
        }

        /// 自定义解码：parameters 字段从 JSON 对象还原为 [String: Any]
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            description = try container.decode(String.self, forKey: .description)
            let raw = try container.decode(AnyCodable.self, forKey: .parameters)
            parameters = raw.value as? [String: Any] ?? [:]
        }

        /// 自定义编码：parameters 字段通过 AnyCodable 转为可编码形式
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(description, forKey: .description)
            try container.encode(AnyCodable(parameters), forKey: .parameters)
        }

        // MARK: - Hashable

        /// 基于 parameters 的 JSON Data 进行哈希，保证 [String: Any] 的稳定哈希
        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(description)
            if let data = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]) {
                hasher.combine(data)
            }
        }

        /// 基于 parameters 的 JSON Data 进行相等性比较
        public static func == (lhs: PluginToolDef, rhs: PluginToolDef) -> Bool {
            guard lhs.name == rhs.name, lhs.description == rhs.description else { return false }
            let lhsData = try? JSONSerialization.data(withJSONObject: lhs.parameters, options: [.sortedKeys])
            let rhsData = try? JSONSerialization.data(withJSONObject: rhs.parameters, options: [.sortedKeys])
            return lhsData == rhsData
        }

        /// 普通构造器，供外部直接创建
        public init(name: String, description: String, parameters: [String: Any]) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }
}
