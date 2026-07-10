import Foundation

/// DeepSeek SSE 流解析器，@unchecked Sendable 允许跨 actor 使用
final class SSEParser: @unchecked Sendable {
    /// 解析原始 Data 为字符串（当前实现仅转码，未实际使用）
    func parse(data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// 解析单行 SSE 为 ChatChunk。跳过非 `data: ` 前缀行和 `[DONE]`。解码失败返回 nil。
    func parseChunk(from line: String) -> ChatChunk? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonString = String(line.dropFirst(6))
        guard jsonString != "[DONE]" else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatChunk.self, from: data)
    }

    /// 解析单行 SSE 并跨 chunk 累积 tool_calls。
    /// - Parameters:
    ///   - line: SSE 行
    ///   - accumulated: 跨 chunk 累积的工具调用字典（key 为 index，value 为 AccumulatedToolCall）
    /// - Returns: ParsedChunk（content 可能为 nil，toolCalls 为累积后的全部工具调用或 nil）。
    ///   tool_calls 的 arguments 字段会分多次到达，需按 index 合并。
    func parseWithToolAccumulation(from line: String, accumulated: inout [Int: AccumulatedToolCall]) -> ParsedChunk? {
        guard let chunk = parseChunk(from: line) else { return nil }
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
