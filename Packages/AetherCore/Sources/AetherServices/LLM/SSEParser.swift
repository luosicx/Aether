import Foundation
import AetherFoundation
import AetherRust

/// DeepSeek SSE 流解析器，@unchecked Sendable 允许跨 actor 使用。
/// 实现已迁移至 Rust（aether-core），本类仅做转发与类型映射。
/// 如需回退到纯 Swift 实现，将 `useRust` 置为 false 即可。
public final class SSEParser: @unchecked Sendable {
    /// 切换开关：true 走 Rust 核心，false 走下方纯 Swift 兜底实现。
    private static let useRust = true
    private let rust = AetherRustSSEParser()

    public init() {}

    /// 解析原始 Data 为字符串（当前实现仅转码，未实际使用）
    public func parse(data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// 解析单行 SSE 为 ChatChunk。跳过非 `data: ` 前缀行和 `[DONE]`。解码失败返回 nil。
    public func parseChunk(from line: String) -> ChatChunk? {
        if Self.useRust {
            guard let content = rust.parseChunk(line) else { return nil }
            // [DONE] 与无 content 行均返回 nil（与旧行为一致：旧实现在 [DONE] 也返回 nil）
            guard let s = content else { return nil }
            // 复用既有 ChatChunk 结构，仅携带 content（与原 parseChunk 在 tool_calls 缺失时的产出对齐）
            let delta = ChatChunk.Delta(content: s)
            let choice = ChatChunk.Choice(delta: delta)
            return ChatChunk(choices: [choice])
        }
        return parseChunkSwift(from: line)
    }

    /// 解析单行 SSE 并跨 chunk 累积 tool_calls。
    /// - Parameters:
    ///   - line: SSE 行
    ///   - accumulated: 跨 chunk 累积的工具调用字典（key 为 index，value 为 AccumulatedToolCall）
    /// - Returns: ParsedChunk（content 可能为 nil，toolCalls 为累积后的全部工具调用或 nil）。
    ///   tool_calls 的 arguments 字段会分多次到达，需按 index 合并。
    public func parseWithToolAccumulation(from line: String, accumulated: inout [Int: AccumulatedToolCall]) -> ParsedChunk? {
        if Self.useRust {
            guard let r = rust.parseWithTools(line) else { return nil }
            // Rust 已按 id 排序并完成跨 chunk 累积，回填到 Swift 字典以保持既有 inout 语义
            accumulated.removeAll()
            if let tcs = r.toolCalls {
                for (i, tc) in tcs.enumerated() {
                    accumulated[i] = AccumulatedToolCall(
                        id: tc.id, type: tc.type, name: tc.name, arguments: tc.arguments
                    )
                }
            }
            let toolCalls = accumulated.isEmpty ? nil : accumulated.values.sorted(by: { $0.id < $1.id })
            return ParsedChunk(content: r.content, toolCalls: toolCalls)
        }
        return parseWithToolAccumulationSwift(from: line, accumulated: &accumulated)
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    private func parseChunkSwift(from line: String) -> ChatChunk? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonString = String(line.dropFirst(6))
        guard jsonString != "[DONE]" else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatChunk.self, from: data)
    }

    private func parseWithToolAccumulationSwift(from line: String, accumulated: inout [Int: AccumulatedToolCall]) -> ParsedChunk? {
        guard let chunk = parseChunkSwift(from: line) else { return nil }
        guard let choice = chunk.choices?.first else { return nil }

        let content = choice.delta?.content

        if let toolDeltas = choice.delta?.tool_calls {
            for td in toolDeltas {
                let idx = td.index ?? 0
                if var existing = accumulated[idx] {
                    if let args = td.function?.arguments {
                        existing.arguments += args
                    }
                    accumulated[idx] = existing
                } else {
                    guard let id = td.id, let name = td.function?.name else { continue }
                    accumulated[idx] = AccumulatedToolCall(
                        id: id,
                        type: td.type ?? "function",
                        name: name,
                        arguments: td.function?.arguments ?? ""
                    )
                }
            }
        }

        let toolCalls = accumulated.isEmpty ? nil : accumulated.values.sorted(by: { $0.id < $1.id })
        return ParsedChunk(content: content, toolCalls: toolCalls)
    }
}
