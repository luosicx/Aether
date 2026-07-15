import Foundation

/// MCP（Model Context Protocol）Server 配置模型。
///
/// 定义 MCP Server 的连接参数：显示名称、传输方式（stdio / SSE）、启用状态。
/// Codable + Hashable：支持序列化持久化与集合操作。
public struct MCPConfig: Codable, Identifiable, Hashable {
    /// 唯一标识（UUID 字符串）
    public let id: String
    /// 显示名称
    public var name: String
    /// 传输方式
    public var transport: Transport
    /// 是否启用
    public var enabled: Bool

    public init(id: String, name: String, transport: Transport, enabled: Bool) {
        self.id = id
        self.name = name
        self.transport = transport
        self.enabled = enabled
    }

    /// MCP 传输方式枚举。
    /// - stdio：通过子进程 stdin/stdout 通信（仅 macOS）
    /// - sse：通过 HTTP SSE 连接（跨平台）
    public enum Transport: Codable, Hashable {
        /// stdio 传输：启动子进程，通过 stdin/stdout 通信
        case stdio(command: String, args: [String], env: [String: String]?)
        /// SSE 传输：通过 URL 建立 SSE 连接
        case sse(url: String, headers: [String: String]?)

        // MARK: - 自定义 Codable（支持带关联值的 enum 编解码）

        private enum CodingKeys: String, CodingKey {
            case type, command, args, env, url, headers
        }

        /// 编码：按 case 写入 type 字段 + 对应关联值字段
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .stdio(let command, let args, let env):
                try container.encode("stdio", forKey: .type)
                try container.encode(command, forKey: .command)
                try container.encode(args, forKey: .args)
                try container.encodeIfPresent(env, forKey: .env)
            case .sse(let url, let headers):
                try container.encode("sse", forKey: .type)
                try container.encode(url, forKey: .url)
                try container.encodeIfPresent(headers, forKey: .headers)
            }
        }

        /// 解码：按 type 字段分支读取关联值
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "stdio":
                let command = try container.decode(String.self, forKey: .command)
                let args = try container.decode([String].self, forKey: .args)
                let env = try container.decodeIfPresent([String: String].self, forKey: .env)
                self = .stdio(command: command, args: args, env: env)
            case "sse":
                let url = try container.decode(String.self, forKey: .url)
                let headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
                self = .sse(url: url, headers: headers)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container,
                    debugDescription: "未知的传输类型: \(type)"
                )
            }
        }
    }
}

/// 已连接 MCP Server 的运行时信息快照。
/// 非 Codable：包含带关联值的 ConnectionStatus，仅用于运行时状态展示。
public struct MCPServerInfo: Identifiable {
    /// 唯一标识（与 MCPConfig.id 对应）
    public let id: String
    /// 显示名称
    public let name: String
    /// 连接状态
    public let status: ConnectionStatus
    /// Server 暴露的工具列表
    public let tools: [MCPTool]
    /// Server 暴露的资源列表
    public let resources: [MCPResource]
    /// Server 暴露的提示模板列表
    public let prompts: [MCPPrompt]

    public init(id: String, name: String, status: ConnectionStatus, tools: [MCPTool], resources: [MCPResource], prompts: [MCPPrompt]) {
        self.id = id
        self.name = name
        self.status = status
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
    }

    /// 连接状态枚举
    public enum ConnectionStatus: Equatable {
        case connected
        case disconnected
        case connecting
        case error(String)
    }
}

/// MCP 工具定义。对应 JSON-RPC tools/list 响应中的 tool 对象。
///
/// 注意：inputSchema 为 JSON Schema（可能包含嵌套结构），使用 [String: Any] 存储。
/// Codable / Hashable 通过自定义实现处理 [String: Any] 的限制。
public struct MCPTool: Identifiable {
    /// 工具名（唯一标识）
    public let name: String
    /// 工具描述
    public let description: String
    /// 输入参数 JSON Schema
    public let inputSchema: [String: Any]

    public init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    /// Identifiable：使用 name 作为唯一标识
    public var id: String { name }
}

// MARK: - MCPTool 自定义 Codable（通过 AnyCodable 中转 [String: Any]）

extension MCPTool: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, description, inputSchema
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        // inputSchema 通过 AnyCodable 解码后转回 [String: Any]
        let schemaDict = try container.decode([String: AnyCodable].self, forKey: .inputSchema)
        inputSchema = schemaDict.mapValues { $0.value }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        // inputSchema 通过 AnyCodable 编码
        try container.encode(inputSchema.mapValues(AnyCodable.init), forKey: .inputSchema)
    }
}

// MARK: - MCPTool 自定义 Hashable（基于 name，因为 [String: Any] 不可 Hashable）

extension MCPTool: Hashable {
    public static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// MCP 资源定义。对应 JSON-RPC resources/list 响应中的 resource 对象。
public struct MCPResource: Codable, Identifiable, Hashable {
    /// 资源 URI（唯一标识）
    public let uri: String
    /// 资源名称
    public let name: String
    /// 资源描述
    public let description: String?
    /// MIME 类型
    public let mimeType: String?

    public init(uri: String, name: String, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }

    /// Identifiable：使用 uri 作为唯一标识
    public var id: String { uri }
}

/// MCP 提示模板定义。对应 JSON-RPC prompts/list 响应中的 prompt 对象。
public struct MCPPrompt: Codable, Identifiable, Hashable {
    /// 提示模板名（唯一标识）
    public let name: String
    /// 提示模板描述
    public let description: String
    /// 参数列表
    public let arguments: [MCPPromptArgument]?

    public init(name: String, description: String, arguments: [MCPPromptArgument]? = nil) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }

    /// Identifiable：使用 name 作为唯一标识
    public var id: String { name }
}

/// MCP 提示模板参数定义。
public struct MCPPromptArgument: Codable, Hashable {
    /// 参数名
    public let name: String
    /// 参数描述
    public let description: String?
    /// 是否必填
    public let required: Bool

    public init(name: String, description: String? = nil, required: Bool) {
        self.name = name
        self.description = description
        self.required = required
    }
}

// MARK: - MCP 方法返回值类型

/// tools/call 返回结果
public struct MCPToolCallResult: Codable, Sendable {
    /// 内容块列表
    public let content: [Content]
    /// 是否为错误响应（可选，缺省为 false）
    public let isError: Bool?

    public init(content: [Content], isError: Bool? = nil) {
        self.content = content
        self.isError = isError
    }

    /// 单个内容块
    public struct Content: Codable, Sendable {
        /// 内容类型（如 "text"）
        public let type: String
        /// 文本内容（type 为 "text" 时有值）
        public let text: String?
        /// base64 编码的二进制数据（type 为 "image" 等时有值）
        public let data: String?
        /// MIME 类型
        public let mimeType: String?

        public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
            self.type = type
            self.text = text
            self.data = data
            self.mimeType = mimeType
        }
    }
}

/// resources/read 返回的单条资源内容
public struct MCPResourceContent: Codable, Sendable {
    /// 资源 URI
    public let uri: String
    /// MIME 类型
    public let mimeType: String?
    /// 文本内容
    public let text: String?
    /// base64 编码的二进制数据
    public let blob: String?

    public init(uri: String, mimeType: String? = nil, text: String? = nil, blob: String? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }
}

/// prompts/get 返回结果
public struct MCPPromptResult: Codable, Sendable {
    /// 提示模板描述
    public let description: String?
    /// 消息列表
    public let messages: [Message]

    public init(description: String? = nil, messages: [Message]) {
        self.description = description
        self.messages = messages
    }

    /// 单条消息
    public struct Message: Codable, Sendable {
        /// 角色（如 "user" / "assistant"）
        public let role: String
        /// 消息内容
        public let content: Content

        public init(role: String, content: Content) {
            self.role = role
            self.content = content
        }
    }

    /// 消息内容
    public struct Content: Codable, Sendable {
        /// 内容类型（如 "text"）
        public let type: String
        /// 文本内容
        public let text: String?

        public init(type: String, text: String? = nil) {
            self.type = type
            self.text = text
        }
    }
}
