import Foundation
import NaturalLanguage
import AetherRust

/// 文档分块器，按句子切分并累积到 maxChars，相邻块间用 overlap 拼接保证上下文连续性
///
/// 分块逻辑已迁移至 Rust（aether-core，unicode-segmentation UAX #29 句子边界），
/// 统一 Apple/Workers 分块算法，去除 Apple-only `NLTokenizer` 依赖。
/// 如需回退到纯 Swift 实现，将 `useRust` 置为 false 即可。
final class DocumentChunker {
    /// 切换开关：true 走 Rust 核心，false 走下方纯 Swift 兜底实现。
    private static let useRust = true

    /// 单块最大字符数 2048（约 1024-2048 token，安全在 Qwen 单行 8192 token 限制内）
    private let maxChars = 2048
    /// 相邻块重叠字符数 256
    private let overlapChars = 256

    /// 分块主流程。返回 DocumentChunk 数组（chunkIndex 从 0 递增）。
    func chunkDocument(_ text: String, source: String) -> [DocumentChunk] {
        if Self.useRust {
            let chunks = AetherRustChunker.chunkDocument(text, maxChars: maxChars, overlapChars: overlapChars)
            return chunks.enumerated().map { idx, content in
                DocumentChunk(content: content, source: source, chunkIndex: idx)
            }
        }
        return chunkDocumentSwift(text, source: source)
    }

    // MARK: - 纯 Swift 兜底实现（保留以便回退）

    /// 三阶段：1) 用 NLTokenizer(unit: .sentence) 按句子切分；
    /// 2) 累积句子到 maxChars，超出时落盘当前块；
    /// 3) 用前一块的 suffix(overlapChars) 作为下一块的 overlap 拼接。
    private func chunkDocumentSwift(_ text: String, source: String) -> [DocumentChunk] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        var chunks: [DocumentChunk] = []
        var currentChunk = ""
        for sentence in sentences {
            if currentChunk.count + sentence.count > maxChars {
                if !currentChunk.isEmpty {
                    chunks.append(DocumentChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), source: source, chunkIndex: chunks.count))
                }
                let overlapText = currentChunk.count > overlapChars ? String(currentChunk.suffix(overlapChars)) : ""
                currentChunk = overlapText + sentence
            } else {
                currentChunk += sentence
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(DocumentChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), source: source, chunkIndex: chunks.count))
        }
        return chunks
    }
}
