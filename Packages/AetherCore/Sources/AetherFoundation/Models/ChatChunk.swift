import Foundation

/// DeepSeek chat completions SSE 流式响应的 chunk 结构
public struct ChatChunk: Codable, Sendable {
    public let id: String?
    public let choices: [Choice]?
    public let usage: Usage?

    /// 单个候选结果，包含 delta 增量与 finish_reason
    public struct Choice: Codable, Sendable {
        public let delta: Delta?
        public let finish_reason: String?

        public init(delta: Delta? = nil, finish_reason: String? = nil) {
            self.delta = delta
            self.finish_reason = finish_reason
        }
    }

    /// 增量内容，包含 role / content / tool_calls
    public struct Delta: Codable, Sendable {
        public let role: String?
        public let content: String?
        public let tool_calls: [ToolCallDelta]?

        public init(role: String? = nil, content: String? = nil, tool_calls: [ToolCallDelta]? = nil) {
            self.role = role
            self.content = content
            self.tool_calls = tool_calls
        }
    }

    /// 工具调用增量，按 index 累积
    public struct ToolCallDelta: Codable, Sendable {
        public let index: Int?
        public let id: String?
        public let type: String?
        public let function: FunctionDelta?

        public init(index: Int? = nil, id: String? = nil, type: String? = nil, function: FunctionDelta? = nil) {
            self.index = index
            self.id = id
            self.type = type
            self.function = function
        }
    }

    /// 工具调用的函数增量；name 通常仅在首 chunk 出现，arguments 跨多个 chunk 拼接
    public struct FunctionDelta: Codable, Sendable {
        public let name: String?
        public let arguments: String?

        public init(name: String? = nil, arguments: String? = nil) {
            self.name = name
            self.arguments = arguments
        }
    }

    /// token 用量统计（通常仅在最后一个 chunk 出现）
    public struct Usage: Codable, Sendable {
        public let prompt_tokens: Int?
        public let completion_tokens: Int?
        public let total_tokens: Int?

        public init(prompt_tokens: Int? = nil, completion_tokens: Int? = nil, total_tokens: Int? = nil) {
            self.prompt_tokens = prompt_tokens
            self.completion_tokens = completion_tokens
            self.total_tokens = total_tokens
        }
    }

    public init(id: String? = nil, choices: [Choice]? = nil, usage: Usage? = nil) {
        self.id = id
        self.choices = choices
        self.usage = usage
    }
}

/// 跨多个 SSE chunk 累积的工具调用（arguments 字段可能分多次到达）
public struct AccumulatedToolCall: Sendable {
    public let id: String
    public let type: String
    public let name: String
    public var arguments: String

    public init(id: String, type: String, name: String, arguments: String) {
        self.id = id
        self.type = type
        self.name = name
        self.arguments = arguments
    }
}

extension AccumulatedToolCall {
    /// 转换为 ChatRequestBody.ToolCallBody，用于后续请求中携带历史工具调用
    /// - Returns: 与请求体结构对应的 ToolCallBody
    public func toToolCallBody() -> ChatRequestBody.ToolCallBody {
        ChatRequestBody.ToolCallBody(id: id, type: type, function: ChatRequestBody.FunctionBody(name: name, arguments: arguments))
    }
}

/// SSEParser 解析后的结果；content 可能为 nil（纯 tool_calls chunk），toolCalls 可能为 nil（纯 content chunk）
public struct ParsedChunk: Sendable {
    public let content: String?
    public let toolCalls: [AccumulatedToolCall]?

    public init(content: String? = nil, toolCalls: [AccumulatedToolCall]? = nil) {
        self.content = content
        self.toolCalls = toolCalls
    }
}

/// DeepSeek chat completions 请求体
public struct ChatRequestBody: Codable {
    public let model: String
    public let messages: [ChatMessageBody]
    public let stream: Bool
    public let max_tokens: Int?
    public let temperature: Double?
    public let tools: [ToolDef]?
    public let tool_choice: String?

    public init(model: String, messages: [ChatMessageBody], stream: Bool, max_tokens: Int? = nil, temperature: Double? = nil, tools: [ToolDef]? = nil, tool_choice: String? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.tools = tools
        self.tool_choice = tool_choice
    }

    /// 请求中的消息结构（含自定义 encode/decode 支持可选字段，仅编码非 nil 字段）
    public struct ChatMessageBody: Codable, Sendable {
        public let role: String
        public let content: String?
        public let images: [String]?
        public let tool_call_id: String?
        public let tool_calls: [ToolCallBody]?

        enum CodingKeys: String, CodingKey {
            case role, content, images, tool_call_id, tool_calls
        }

        public init(role: String, content: String?, images: [String]?, tool_call_id: String?, tool_calls: [ToolCallBody]?) {
            self.role = role
            self.content = content
            self.images = images
            self.tool_call_id = tool_call_id
            self.tool_calls = tool_calls
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decode(String.self, forKey: .role)
            content = try c.decodeIfPresent(String.self, forKey: .content)
            images = try c.decodeIfPresent([String].self, forKey: .images)
            tool_call_id = try c.decodeIfPresent(String.self, forKey: .tool_call_id)
            tool_calls = try c.decodeIfPresent([ToolCallBody].self, forKey: .tool_calls)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encodeIfPresent(content, forKey: .content)
            try c.encodeIfPresent(images, forKey: .images)
            try c.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
            try c.encodeIfPresent(tool_calls, forKey: .tool_calls)
        }
    }

    /// 请求中的工具调用结构，对应 assistant 消息中已触发的 tool_calls
    public struct ToolCallBody: Codable, Sendable {
        public let id: String
        public let type: String
        public let function: FunctionBody

        public init(id: String, type: String, function: FunctionBody) {
            self.id = id
            self.type = type
            self.function = function
        }
    }

    /// 工具调用的函数体，含工具名与参数 JSON 字符串
    public struct FunctionBody: Codable, Sendable {
        public let name: String
        public let arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }
}

/// 工具定义（OpenAI function calling 格式），type 固定为 "function"
public struct ToolDef: Codable {
    public let type: String
    public let function: FunctionDef

    public init(type: String, function: FunctionDef) {
        self.type = type
        self.function = function
    }

    /// 工具定义体：含工具名、描述、parameters JSON Schema
    public struct FunctionDef: Codable {
        public let name: String
        public let description: String
        public let parameters: [String: AnyCodable]

        public init(name: String, description: String, parameters: [String: AnyCodable]) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }
}

/// 动态类型包装器，用于 ToolDef.parameters 的 JSON Schema 字典
/// （Swift Codable 不直接支持 [String: Any]，用此包装器实现动态编解码）
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = ()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            try container.encodeNil()
        }
    }
}

/// DeepSeek embedding API 响应
public struct EmbeddingResponse: Codable, Sendable {
    public let data: [EmbeddingData]
    public let usage: Usage?

    public init(data: [EmbeddingData], usage: Usage? = nil) {
        self.data = data
        self.usage = usage
    }

    /// 单条文本的向量嵌入结果
    public struct EmbeddingData: Codable, Sendable {
        public let embedding: [Float]
        public let index: Int

        public init(embedding: [Float], index: Int) {
            self.embedding = embedding
            self.index = index
        }
    }

    /// embedding API 的 token 用量统计
    public struct Usage: Codable, Sendable {
        public let prompt_tokens: Int?
        public let total_tokens: Int?

        public init(prompt_tokens: Int? = nil, total_tokens: Int? = nil) {
            self.prompt_tokens = prompt_tokens
            self.total_tokens = total_tokens
        }
    }
}

/// Day 10: 统一 LLM 错误类型，供 UI 转成用户友好提示
public enum LLMError: Error, Sendable, LocalizedError {
    /// 网络连接错误（如断网、DNS 失败）
    case networkError(String)        // 网络连接错误
    /// API Key 缺失（用户未在设置中配置）
    case apiKeyMissing               // API Key 缺失
    /// API Key 无效（HTTP 401）
    case apiKeyInvalid               // API Key 无效（401）
    /// 其它 API 错误，携带状态码与原始消息
    case apiError(code: Int, message: String)  // 其它 API 错误
    /// 请求超时
    case timeout                     // 请求超时
    /// 未知错误（未匹配到上述分类的异常）
    case unknown(String)             // 未知错误
    /// Day 15: 触发限流（客户端令牌桶耗尽或服务端 429），携带建议重试秒数
    case rateLimited(retryAfter: TimeInterval)
    /// Day 15: BFF 通用错误（携带自定义用户可见消息，如 Token 无效 / 服务异常）
    case llmErrorOccurred(String)

    /// 转成用户友好的错误消息（不暴露原始 HTTP 响应）
    /// 按 case 映射；apiError 按 code 进一步细分（400 / 402 / 429 / 5xx）
    public var userMessage: String {
        switch self {
        case .networkError:
            return NSLocalizedString("网络连接失败，请检查网络后重试", comment: "")
        case .apiKeyMissing:
            return NSLocalizedString("API Key 未配置，请前往设置页面配置", comment: "")
        case .apiKeyInvalid:
            return NSLocalizedString("API Key 无效，请检查设置", comment: "")
        case .apiError(let code, _):
            switch code {
            case 400: return NSLocalizedString("请求格式错误，请重试", comment: "")
            case 402: return NSLocalizedString("账户余额不足", comment: "")
            case 429: return NSLocalizedString("请求过于频繁，请稍后再试", comment: "")
            case 500...599: return NSLocalizedString("服务暂时不可用，请稍后再试", comment: "")
            default: return String(format: NSLocalizedString("服务异常（%d），请稍后再试", comment: ""), code)
            }
        case .timeout:
            return NSLocalizedString("请求超时，请检查网络连接后重试", comment: "")
        case .unknown:
            return NSLocalizedString("发生未知错误，请稍后重试或联系支持", comment: "")
        case .rateLimited(let retryAfter):
            return String(format: NSLocalizedString("请求过于频繁，请 %d 秒后重试", comment: ""), Int(retryAfter))
        case .llmErrorOccurred(let message):
            return message
        }
    }

    public var errorDescription: String? {
        userMessage
    }

    /// 从 HTTP 状态码构造 LLMError
    /// 401 → apiKeyInvalid，429 → apiError，其他 → apiError
    public static func fromHTTPStatus(_ code: Int, body: String) -> LLMError {
        switch code {
        case 401: return .apiKeyInvalid
        case 429: return .apiError(code: code, message: body)
        default: return .apiError(code: code, message: body)
        }
    }
}
