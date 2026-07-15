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

    public init(
        id: String,
        name: String,
        version: String,
        author: String,
        description: String,
        tools: [PluginToolDef],
        permissions: [PluginPermission],
        entryPoint: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.tools = tools
        self.permissions = permissions
        self.entryPoint = entryPoint
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
