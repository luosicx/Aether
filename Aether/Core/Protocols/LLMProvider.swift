import Foundation

/// 定义 LLM 客户端契约，抽象 chat 流式对话与 embed 向量嵌入两个核心能力。
protocol LLMProvider: Sendable {
    /// 纯文本 chat 流：以 `AsyncStream<String>` 形式逐 chunk yield 内容。
    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String>
    /// 带工具调用 chat 流：以 `AsyncStream<ParsedChunk>` 形式 yield，包含 content 与累积后的 toolCalls。
    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk>
    /// 批量文本嵌入，返回按 index 排序的向量数组；HTTP 错误抛 `LLMError`。
    func embed(texts: [String], apiKey: String) async throws -> [[Float]]
}

/// 发往 LLM 的消息结构。
struct APIMessage: Sendable {
    /// 角色：`system` / `user` / `assistant` / `tool`。
    let role: String
    /// 文本内容。
    let content: String
    /// base64 编码图片数组，多模态用。
    let images: [String]?
    /// 工具调用 ID，`tool` 角色消息必填。
    let toolCallId: String?
    /// 工具名，`tool` 角色消息必填。
    let toolName: String?
    /// `assistant` 触发的工具调用列表。
    let toolCalls: [ToolCallParam]?
}

/// 一次工具调用的完整参数。
struct ToolCallParam: Sendable {
    /// 工具调用唯一 ID。
    let id: String
    /// 调用类型，通常为 `function`。
    let type: String
    /// 具体函数调用信息。
    let function: FunctionCall
}

/// 工具调用的函数名与参数。
struct FunctionCall: Sendable {
    /// 函数名。
    let name: String
    /// JSON 字符串形式的参数。
    let arguments: String
}
