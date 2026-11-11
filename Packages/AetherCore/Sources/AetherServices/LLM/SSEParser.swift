import Foundation
import AetherFoundation
// 将 AetherRust（含 AetherRustVector / AetherRustSSEParser）透出给 AetherServices 的导入方，
// 使 App target（RAGService / MemoryService 等）无需在 Xcode 工程中单独链接 AetherRust product。
@_exported import AetherRust

/// SSE 流解析器的 Swift 门面，@unchecked Sendable 允许跨 actor 使用。
/// 解析实现统一在 Rust（aether-core），支持 OpenAI `choices[].delta` 与
/// BFF `{"type":"delta"|"done"|"error"}` 两种 envelope。
public final class SSEParser: @unchecked Sendable {
    private let rust = AetherRustSSEParser()

    public init() {}

    /// 解析单行 SSE 为 ChatChunk。跳过非 `data: ` 前缀行、`[DONE]` 与无 content 行。
    public func parseChunk(from line: String) -> ChatChunk? {
        guard let content = rust.parseChunk(line) else { return nil }
        guard let text = content else { return nil }
        let delta = ChatChunk.Delta(content: text)
        return ChatChunk(choices: [ChatChunk.Choice(delta: delta)])
    }

    /// 解析单行 SSE 并跨 chunk 累积 tool_calls。
    /// - Parameters:
    ///   - line: SSE 行
    ///   - accumulated: 跨 chunk 累积的工具调用字典（key 为 index，value 为 AccumulatedToolCall）
    /// - Returns: ParsedChunk（content 可能为 nil，toolCalls 为累积后的全部工具调用或 nil，usage 为上游用量）。
    ///   tool_calls 的 arguments 字段会分多次到达，由 Rust 侧按 index 合并。
    public func parseWithToolAccumulation(from line: String, accumulated: inout [Int: AccumulatedToolCall]) -> ParsedChunk? {
        guard let parsed = rust.parseWithTools(line) else { return nil }
        // Rust 已按 id 排序并完成跨 chunk 累积，回填到 Swift 字典以保持既有 inout 语义
        accumulated.removeAll()
        if let toolCalls = parsed.toolCalls {
            for (index, toolCall) in toolCalls.enumerated() {
                accumulated[index] = AccumulatedToolCall(
                    id: toolCall.id,
                    type: toolCall.type,
                    name: toolCall.name,
                    arguments: toolCall.arguments
                )
            }
        }
        let toolCalls = accumulated.isEmpty ? nil : accumulated.values.sorted(by: { $0.id < $1.id })
        let usage = parsed.usage.map {
            ChatChunk.Usage(
                prompt_tokens: $0.prompt_tokens,
                completion_tokens: $0.completion_tokens,
                total_tokens: $0.total_tokens
            )
        }
        return ParsedChunk(content: parsed.content, toolCalls: toolCalls, usage: usage)
    }
}
