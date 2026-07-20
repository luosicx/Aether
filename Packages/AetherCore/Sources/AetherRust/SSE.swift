import Foundation
import AetherRustC

/// Swift 友好的 Rust SSE 解析器包装。
///
/// 所有 C ABI 返回的字符串均通过 `aether_free_string` 显式释放（见 `takeString`）。
/// `AetherSseState` 由 Rust 拥有，`deinit` 时调用 `aether_sse_state_free` 释放。
///
/// 线程安全契约：实例应仅在单一 actor / 串行上下文中使用（如每个 LLM client
/// 持有自己的 `SSEParser` 实例）。`parseWithTools` 使用 Rust 侧 `state` 累积
/// 跨 chunk 状态，跨 actor 共享需在调用点加 NSLock。
/// `extractContent` / `parseChunk` 是纯函数，无状态依赖，可并发调用。
public final class AetherRustSSEParser: @unchecked Sendable {
    private let state: OpaquePointer

    public init() {
        state = aether_sse_state_new()
    }

    deinit {
        aether_sse_state_free(state)
    }

    /// 等价于 Workers `parseSSEEvent`：返回 content 字符串或 nil。
    public func extractContent(_ line: String) -> String? {
        guard let raw = line.withCString({ aether_sse_extract_content($0) }) else { return nil }
        return takeString(raw)
    }

    /// 等价于 Swift `parseChunk`：
    /// - 返回 nil：非 data 行 / 解析失败
    /// - 返回 .some(nil)：`data: [DONE]`
    /// - 返回 .some(s)：有 content（可能为空串）
    public func parseChunk(_ line: String) -> String?? {
        guard let raw = line.withCString({ aether_sse_parse_chunk($0) }) else { return nil }
        guard let json = takeString(raw) else { return nil }
        if json == "null" { return .some(nil) }
        // json 形如 "\"Hello\""
        guard let data = json.data(using: .utf8),
              let s = try? JSONDecoder().decode(String.self, from: data) else { return nil }
        return s
    }

    /// 等价于 Swift `parseWithToolAccumulation`。
    /// 返回 (content, toolCalls)；非 data 行返回 nil。
    public func parseWithTools(_ line: String) -> (content: String?, toolCalls: [AetherRustAccumulatedToolCall]?)? {
        guard let raw = line.withCString({ aether_sse_parse_with_tools($0, state) }) else { return nil }
        guard let json = takeString(raw) else { return nil }
        guard let data = json.data(using: .utf8),
              let view = try? JSONDecoder().decode(ParsedChunkView.self, from: data) else { return nil }
        return (view.content, view.toolCalls)
    }

    private func takeString(_ raw: UnsafeMutablePointer<CChar>) -> String? {
        defer { aether_free_string(raw) }
        return String(cString: raw, encoding: .utf8)
    }
}

/// Rust 返回的 JSON 视图（camelCase 字段，与 FFI View 对齐）。
private struct ParsedChunkView: Decodable {
    let content: String?
    let toolCalls: [AetherRustAccumulatedToolCall]?
}

/// `AetherRust` 暴露的累积工具调用（字段 `type` 对应 Rust `kind`，已通过 serde rename 对齐）。
public struct AetherRustAccumulatedToolCall: Decodable {
    public let id: String
    public let type: String
    public let name: String
    public let arguments: String
}
