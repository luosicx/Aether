import Foundation
import NaturalLanguage

/// 文档分块器，按句子切分并累积到 maxChars，相邻块间用 overlap 拼接保证上下文连续性
final class DocumentChunker {
    /// 单块最大字符数 2048（约 1024-2048 token，安全在 Qwen 单行 8192 token 限制内）
    private let maxChars = 2048
    /// 相邻块重叠字符数 256
    private let overlapChars = 256

    /// 分块主流程。三阶段：1) 用 NLTokenizer(unit: .sentence) 按句子切分；
    /// 2) 累积句子到 maxChars，超出时落盘当前块；
    /// 3) 用前一块的 suffix(overlapChars) 作为下一块的 overlap 拼接。
    /// 返回 DocumentChunk 数组（chunkIndex 从 0 递增）。
    func chunkDocument(_ text: String, source: String) -> [DocumentChunk] {
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
