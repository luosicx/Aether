import Foundation

/// DeepSeek chat completions SSE 流式响应的 chunk 结构
struct ChatChunk: Codable, Sendable {
    let id: String?
    let choices: [Choice]?
    let usage: Usage?

    /// 单个候选结果，包含 delta 增量与 finish_reason
    struct Choice: Codable, Sendable {
        let delta: Delta?
        let finish_reason: String?
    }

    /// 增量内容，包含 role / content / tool_calls
    struct Delta: Codable, Sendable {
        let role: String?
        let content: String?
        let tool_calls: [ToolCallDelta]?
    }

    /// 工具调用增量，按 index 累积
    struct ToolCallDelta: Codable, Sendable {
        let index: Int?
        let id: String?
        let type: String?
        let function: FunctionDelta?
    }

    /// 工具调用的函数增量；name 通常仅在首 chunk 出现，arguments 跨多个 chunk 拼接
    struct FunctionDelta: Codable, Sendable {
        let name: String?
        let arguments: String?
    }

    /// token 用量统计（通常仅在最后一个 chunk 出现）
    struct Usage: Codable, Sendable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}

/// 跨多个 SSE chunk 累积的工具调用（arguments 字段可能分多次到达）
struct AccumulatedToolCall: Sendable {
    let id: String
    let type: String
    let name: String
    var arguments: String
}

extension AccumulatedToolCall {
    /// 转换为 ChatRequestBody.ToolCallBody，用于后续请求中携带历史工具调用
    /// - Returns: 与请求体结构对应的 ToolCallBody
    func toToolCallBody() -> ChatRequestBody.ToolCallBody {
        ChatRequestBody.ToolCallBody(id: id, type: type, function: ChatRequestBody.FunctionBody(name: name, arguments: arguments))
    }
}

/// SSEParser 解析后的结果；content 可能为 nil（纯 tool_calls chunk），toolCalls 可能为 nil（纯 content chunk）
struct ParsedChunk: Sendable {
    let content: String?
    let toolCalls: [AccumulatedToolCall]?
}

/// DeepSeek chat completions 请求体
struct ChatRequestBody: Codable {
    let model: String
    let messages: [ChatMessageBody]
    let stream: Bool
    let max_tokens: Int?
    let temperature: Double?
    let tools: [ToolDef]?
    let tool_choice: String?

    /// 请求中的消息结构（含自定义 encode/decode 支持可选字段，仅编码非 nil 字段）
    struct ChatMessageBody: Codable, Sendable {
        let role: String
        let content: String?
        let images: [String]?
        let tool_call_id: String?
        let tool_calls: [ToolCallBody]?

        enum CodingKeys: String, CodingKey {
            case role, content, images, tool_call_id, tool_calls
        }

        init(role: String, content: String?, images: [String]?, tool_call_id: String?, tool_calls: [ToolCallBody]?) {
            self.role = role
            self.content = content
            self.images = images
            self.tool_call_id = tool_call_id
            self.tool_calls = tool_calls
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decode(String.self, forKey: .role)
            content = try c.decodeIfPresent(String.self, forKey: .content)
            images = try c.decodeIfPresent([String].self, forKey: .images)
            tool_call_id = try c.decodeIfPresent(String.self, forKey: .tool_call_id)
            tool_calls = try c.decodeIfPresent([ToolCallBody].self, forKey: .tool_calls)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encodeIfPresent(content, forKey: .content)
            try c.encodeIfPresent(images, forKey: .images)
            try c.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
            try c.encodeIfPresent(tool_calls, forKey: .tool_calls)
        }
    }

    /// 请求中的工具调用结构，对应 assistant 消息中已触发的 tool_calls
    struct ToolCallBody: Codable, Sendable {
        let id: String
        let type: String
        let function: FunctionBody
    }

    /// 工具调用的函数体，含工具名与参数 JSON 字符串
    struct FunctionBody: Codable, Sendable {
        let name: String
        let arguments: String
    }
}

/// 工具定义（OpenAI function calling 格式），type 固定为 "function"
struct ToolDef: Codable {
    let type: String
    let function: FunctionDef

    /// 工具定义体：含工具名、描述、parameters JSON Schema
    struct FunctionDef: Codable {
        let name: String
        let description: String
        let parameters: [String: AnyCodable]
    }
}

/// 动态类型包装器，用于 ToolDef.parameters 的 JSON Schema 字典
/// （Swift Codable 不直接支持 [String: Any]，用此包装器实现动态编解码）
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        if let dict = value as? [String: Any] {
            self.value = dict.mapValues { AnyCodable($0) }
        } else if let array = value as? [Any] {
            self.value = array.map { AnyCodable($0) }
        } else {
            self.value = value
        }
    }

    init(from decoder: Decoder) throws {
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
            value = array
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else {
            value = ()
        }
    }

    func encode(to encoder: Encoder) throws {
        if let int = value as? Int {
            var container = encoder.singleValueContainer()
            try container.encode(int)
        } else if let double = value as? Double {
            var container = encoder.singleValueContainer()
            try container.encode(double)
        } else if let bool = value as? Bool {
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        } else if let string = value as? String {
            var container = encoder.singleValueContainer()
            try container.encode(string)
        } else if let array = value as? [AnyCodable] {
            var container = encoder.unkeyedContainer()
            try container.encode(contentsOf: array)
        } else if let dict = value as? [String: AnyCodable] {
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, value) in dict {
                try container.encode(value, forKey: AnyCodingKey(stringValue: key))
            }
        } else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

/// 动态编码字典时使用的通用 CodingKey
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// DeepSeek embedding API 响应
struct EmbeddingResponse: Codable, Sendable {
    let data: [EmbeddingData]
    let usage: Usage?

    /// 单条文本的向量嵌入结果
    struct EmbeddingData: Codable, Sendable {
        let embedding: [Float]
        let index: Int
    }

    /// embedding API 的 token 用量统计
    struct Usage: Codable, Sendable {
        let prompt_tokens: Int?
        let total_tokens: Int?
    }
}

/// Day 10: 统一 LLM 错误类型，供 UI 转成用户友好提示
enum LLMError: Error, Sendable, LocalizedError {
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
    var userMessage: String {
        switch self {
        case .networkError:
            return NSLocalizedString("网络连接失败，请检查网络", comment: "")
        case .apiKeyMissing:
            return NSLocalizedString("请先在设置中配置 API Key", comment: "")
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
            return NSLocalizedString("请求超时，请重试", comment: "")
        case .unknown:
            return NSLocalizedString("未知错误，请重试", comment: "")
        case .rateLimited(let retryAfter):
            return String(format: NSLocalizedString("请求过于频繁，请 %d 秒后重试", comment: ""), Int(retryAfter))
        case .llmErrorOccurred(let message):
            return message
        }
    }

    var errorDescription: String? {
        userMessage
    }

    /// 从 HTTP 状态码构造 LLMError
    /// 401 → apiKeyInvalid，429 → apiError，其他 → apiError
    static func fromHTTPStatus(_ code: Int, body: String) -> LLMError {
        switch code {
        case 401: return .apiKeyInvalid
        case 429: return .apiError(code: code, message: body)
        default: return .apiError(code: code, message: body)
        }
    }
}
