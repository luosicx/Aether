import Foundation

/// Task 24: Aether SDK 流式响应的单个 chunk。
///
/// `AetherClient.stream(messages:)` 返回 `AsyncStream<AetherChunk>`。
/// 每个 chunk 可能包含文本增量或工具调用（或两者皆有，或皆空）。
public struct AetherChunk: Sendable, Equatable {
    /// 文本内容增量（可能为 nil，如纯 tool_calls chunk）
    public let content: String?
    /// 累积后的工具调用列表（可能为 nil，如纯 content chunk）
    public let toolCalls: [AetherToolCall]?
    /// 是否为流式结束 chunk
    public let isFinal: Bool

    /// 创建 chunk
    /// - Parameters:
    ///   - content: 文本增量
    ///   - toolCalls: 工具调用列表
    ///   - isFinal: 是否为结束 chunk
    public init(content: String? = nil, toolCalls: [AetherToolCall]? = nil, isFinal: Bool = false) {
        self.content = content
        self.toolCalls = toolCalls
        self.isFinal = isFinal
    }

    /// 创建纯文本 chunk
    public static func text(_ content: String) -> AetherChunk {
        AetherChunk(content: content)
    }

    /// 创建纯工具调用 chunk
    public static func toolCalls(_ calls: [AetherToolCall]) -> AetherChunk {
        AetherChunk(toolCalls: calls)
    }

    /// 创建结束 chunk
    public static func final() -> AetherChunk {
        AetherChunk(isFinal: true)
    }
}
