import Foundation
import NaturalLanguage

/// 文档分块器，按句子切分并累积到 maxTokens，相邻块间用 overlap 拼接保证上下文连续性
final class DocumentChunker {
    /// 单块最大 token 数 512（用 estimatedTokens 估算）
    private let maxTokens = 512
    /// 相邻块重叠 token 数 128（实际取 overlap*4 字符作为重叠文本）
    private let overlap = 128

    /// 分块主流程。三阶段：1) 用 NLTokenizer(unit: .sentence) 按句子切分；
    /// 2) 累积句子到 maxTokens，超出时落盘当前块；
    /// 3) 用前一块的 suffix(overlap*4) 作为下一块的 overlap 拼接。
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
        var currentTokens = 0
        for sentence in sentences {
            let sentenceTokens = sentence.estimatedTokens
            if currentTokens + sentenceTokens > maxTokens {
                if !currentChunk.isEmpty {
                    chunks.append(DocumentChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), source: source, chunkIndex: chunks.count))
                }
                let overlapText = currentChunk.count > overlap * 4 ? String(currentChunk.suffix(overlap * 4)) : ""
                currentChunk = overlapText + sentence
                currentTokens = currentChunk.estimatedTokens
            } else {
                currentChunk += sentence
                currentTokens += sentenceTokens
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(DocumentChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), source: source, chunkIndex: chunks.count))
        }
        return chunks
    }
}
