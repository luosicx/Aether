import Foundation

/// MCP（Model Context Protocol）Server 配置模型。
///
/// 定义 MCP Server 的连接参数：显示名称、传输方式（stdio / SSE）、启用状态。
/// Codable + Hashable：支持序列化持久化与集合操作。
struct MCPConfig: Codable, Identifiable, Hashable {
    /// 唯一标识（UUID 字符串）
    let id: String
    /// 显示名称
    var name: String
    /// 传输方式
    var transport: Transport
    /// 是否启用
    var enabled: Bool

    /// MCP 传输方式枚举。
    /// - stdio：通过子进程 stdin/stdout 通信（仅 macOS）
    /// - sse：通过 HTTP SSE 连接（跨平台）
    enum Transport: Codable, Hashable {
        /// stdio 传输：启动子进程，通过 stdin/stdout 通信
        case stdio(command: String, args: [String], env: [String: String]?)
        /// SSE 传输：通过 URL 建立 SSE 连接
        case sse(url: String, headers: [String: String]?)

        // MARK: - 自定义 Codable（支持带关联值的 enum 编解码）

        private enum CodingKeys: String, CodingKey {
            case type, command, args, env, url, headers
        }

        /// 编码：按 case 写入 type 字段 + 对应关联值字段
        func encode(to encoder: Encoder) throws {
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
        init(from decoder: Decoder) throws {
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
struct MCPServerInfo: Identifiable {
    /// 唯一标识（与 MCPConfig.id 对应）
    let id: String
    /// 显示名称
    let name: String
    /// 连接状态
    let status: ConnectionStatus
    /// Server 暴露的工具列表
    let tools: [MCPTool]
    /// Server 暴露的资源列表
    let resources: [MCPResource]
    /// Server 暴露的提示模板列表
    let prompts: [MCPPrompt]

    /// 连接状态枚举
    enum ConnectionStatus: Equatable {
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
struct MCPTool: Identifiable {
    /// 工具名（唯一标识）
    let name: String
    /// 工具描述
    let description: String
    /// 输入参数 JSON Schema
    let inputSchema: [String: Any]

    /// Identifiable：使用 name 作为唯一标识
    var id: String { name }
}

// MARK: - MCPTool 自定义 Codable（通过 AnyCodable 中转 [String: Any]）

extension MCPTool: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, description, inputSchema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        // inputSchema 通过 AnyCodable 解码后转回 [String: Any]
        let schemaDict = try container.decode([String: AnyCodable].self, forKey: .inputSchema)
        inputSchema = schemaDict.mapValues { $0.value }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        // inputSchema 通过 AnyCodable 编码
        try container.encode(inputSchema.mapValues(AnyCodable.init), forKey: .inputSchema)
    }
}

// MARK: - MCPTool 自定义 Hashable（基于 name，因为 [String: Any] 不可 Hashable）

extension MCPTool: Hashable {
    static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// MCP 资源定义。对应 JSON-RPC resources/list 响应中的 resource 对象。
struct MCPResource: Codable, Identifiable, Hashable {
    /// 资源 URI（唯一标识）
    let uri: String
    /// 资源名称
    let name: String
    /// 资源描述
    let description: String?
    /// MIME 类型
    let mimeType: String?

    /// Identifiable：使用 uri 作为唯一标识
    var id: String { uri }
}

/// MCP 提示模板定义。对应 JSON-RPC prompts/list 响应中的 prompt 对象。
struct MCPPrompt: Codable, Identifiable, Hashable {
    /// 提示模板名（唯一标识）
    let name: String
    /// 提示模板描述
    let description: String
    /// 参数列表
    let arguments: [MCPPromptArgument]?

    /// Identifiable：使用 name 作为唯一标识
    var id: String { name }
}

/// MCP 提示模板参数定义。
struct MCPPromptArgument: Codable, Hashable {
    /// 参数名
    let name: String
    /// 参数描述
    let description: String?
    /// 是否必填
    let required: Bool
}

// MARK: - MCP 方法返回值类型

/// tools/call 返回结果
struct MCPToolCallResult: Codable, Sendable {
    /// 内容块列表
    let content: [Content]
    /// 是否为错误响应（可选，缺省为 false）
    let isError: Bool?

    /// 单个内容块
    struct Content: Codable, Sendable {
        /// 内容类型（如 "text"）
        let type: String
        /// 文本内容（type 为 "text" 时有值）
        let text: String?
        /// base64 编码的二进制数据（type 为 "image" 等时有值）
        let data: String?
        /// MIME 类型
        let mimeType: String?
    }
}

/// resources/read 返回的单条资源内容
struct MCPResourceContent: Codable, Sendable {
    /// 资源 URI
    let uri: String
    /// MIME 类型
    let mimeType: String?
    /// 文本内容
    let text: String?
    /// base64 编码的二进制数据
    let blob: String?
}

/// prompts/get 返回结果
struct MCPPromptResult: Codable, Sendable {
    /// 提示模板描述
    let description: String?
    /// 消息列表
    let messages: [Message]

    /// 单条消息
    struct Message: Codable, Sendable {
        /// 角色（如 "user" / "assistant"）
        let role: String
        /// 消息内容
        let content: Content
    }

    /// 消息内容
    struct Content: Codable, Sendable {
        /// 内容类型（如 "text"）
        let type: String
        /// 文本内容
        let text: String?
    }
}
