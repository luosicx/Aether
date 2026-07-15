import Foundation
import AetherRustC

/// Swift 友好的 Rust 文档分块包装。
///
/// 将 `DocumentChunker`（Apple `NLTokenizer`）迁移至 Rust `unicode-segmentation`
/// crate（UAX #29 句子边界），统一 Apple/Workers 分块算法，去除 Apple-only 依赖。
public enum AetherRustChunker {
    /// 对文档分块，返回块文本列表（已 trim，下标即 chunkIndex）。
    ///
    /// 算法：按 UAX #29 句子边界切分 → 累积到 `maxChars` 后落盘 →
    /// 相邻块用 `overlapChars` 个字符拼接保证上下文连续。
    /// 与 `DocumentChunker.chunkDocument` 的纯 Swift 实现行为一致。
    public static func chunkDocument(_ text: String, maxChars: Int, overlapChars: Int) -> [String] {
        return text.withCString { ptr in
            guard let raw = aether_chunk_document(ptr, maxChars, overlapChars) else {
                return [text]
            }
            defer { aether_free_string(raw) }
            let json = String(cString: raw)
            guard let data = json.data(using: .utf8),
                  let chunks = try? JSONDecoder().decode([String].self, from: data) else {
                return [text]
            }
            return chunks
        }
    }
}
