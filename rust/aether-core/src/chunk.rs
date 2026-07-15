//! 文档分块器：按句子切分并累积到 maxChars，相邻块间用 overlap 拼接。
//!
//! 统一 Apple（`DocumentChunker.swift`，原用 `NLTokenizer`）与
//! CloudflareWorkers（`rag.js` `chunkText`，原按固定字符滑窗）的分块算法。
//! 句子边界用 `unicode-segmentation` 的 UAX #29 实现，去除 Apple-only 依赖。

use unicode_segmentation::UnicodeSegmentation;

/// 对文档分块，返回块文本列表（已 trim，chunkIndex 即数组下标）。
///
/// 算法三阶段：
/// 1. 用 UAX #29 句子边界按句子切分（跨语言，中文友好）；
/// 2. 累积句子到超过 `max_chars` 时落盘当前块；
/// 3. 用前一块的尾部 `overlap_chars` 个字符作为下一块的 overlap 拼接。
///
/// - `max_chars == 0` 或空文本返回空列表。
/// - 单句超长时不二次切分（与 Apple 原实现一致，避免破坏句子语义）。
/// - 按 Unicode 标量值计数（`chars().count()`），与 Swift `String.count` 近似。
pub fn chunk_document(text: &str, max_chars: usize, overlap_chars: usize) -> Vec<String> {
    if text.is_empty() || max_chars == 0 {
        return Vec::new();
    }

    let sentences: Vec<&str> = text.unicode_sentences().collect();
    let mut chunks: Vec<String> = Vec::new();
    let mut current = String::new();

    for sentence in sentences {
        let current_len = current.chars().count();
        let sentence_len = sentence.chars().count();
        if current_len + sentence_len > max_chars {
            if !current.is_empty() {
                let trimmed = current.trim();
                if !trimmed.is_empty() {
                    chunks.push(trimmed.to_string());
                }
            }
            // 取前一块尾部 overlap_chars 个字符作为 overlap
            let overlap = take_suffix_chars(&current, overlap_chars);
            current = overlap + sentence;
        } else {
            current.push_str(sentence);
        }
    }

    let trimmed = current.trim();
    if !trimmed.is_empty() {
        chunks.push(trimmed.to_string());
    }
    chunks
}

/// 取字符串尾部 `n` 个 Unicode 标量值（等价于 Swift `String.suffix(n)`）。
fn take_suffix_chars(s: &str, n: usize) -> String {
    if n == 0 {
        return String::new();
    }
    let chars: Vec<char> = s.chars().collect();
    let total = chars.len();
    if total <= n {
        return s.to_string();
    }
    chars[total - n..].iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_text_returns_empty() {
        assert!(chunk_document("", 2048, 256).is_empty());
    }

    #[test]
    fn max_chars_zero_returns_empty() {
        assert!(chunk_document("hello world", 0, 0).is_empty());
    }

    #[test]
    fn short_text_returns_single_chunk() {
        let text = "Hello world. This is a test.";
        let chunks = chunk_document(text, 2048, 256);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0], "Hello world. This is a test.");
    }

    #[test]
    fn splits_on_sentence_boundary() {
        // 两个句子，每句约 15 字符，max_chars=20 触发切分
        let text = "First sentence. Second one.";
        let chunks = chunk_document(text, 20, 0);
        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0], "First sentence.");
        assert_eq!(chunks[1], "Second one.");
    }

    #[test]
    fn overlap_carries_suffix() {
        // "AAAA. "（6 chars），max_chars=5 触发切分，overlap=3
        // overlap 取自未 trim 的 "AAAA. " 尾部 3 字符 "A. "
        // 第二块 = "A. " + "BBBB." = "A. BBBB."
        let text = "AAAA. BBBB.";
        let chunks = chunk_document(text, 5, 3);
        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0], "AAAA.");
        assert!(chunks[1].starts_with("A. "));
    }

    #[test]
    fn chinese_sentence_boundary() {
        // 中文句号作为句子边界
        let text = "这是第一句话。这是第二句话。这是第三句话。";
        let chunks = chunk_document(text, 20, 0);
        // 每句 9 个字符（含句号），max_chars=20 → 第一块两句，第二块一句
        assert_eq!(chunks.len(), 2);
    }

    #[test]
    fn single_long_sentence_not_split() {
        // 单句超过 max_chars 时不二次切分，整体作为一块
        let text = "thisisaverylongsentencewithoutspacesorpunctuation";
        let chunks = chunk_document(text, 10, 0);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0], text);
    }

    #[test]
    fn chunks_are_trimmed() {
        let text = "Hello. World.";
        let chunks = chunk_document(text, 2048, 256);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0], "Hello. World.");
        // 不应以空白开头或结尾
        assert!(!chunks[0].starts_with(' '));
        assert!(!chunks[0].ends_with(' '));
    }

    #[test]
    fn multiple_paragraphs() {
        let text = "Para one. More text.\nPara two. End here.";
        let chunks = chunk_document(text, 30, 0);
        assert!(chunks.len() >= 2);
    }

    #[test]
    fn overlap_zero_no_carry() {
        let text = "First. Second. Third.";
        let chunks = chunk_document(text, 10, 0);
        assert!(chunks.len() >= 2);
        // overlap=0 时第二块不应携带第一块尾部
        for w in chunks.iter().skip(1) {
            assert!(!w.starts_with('.'));
        }
    }

    #[test]
    fn take_suffix_chars_basic() {
        assert_eq!(take_suffix_chars("hello", 2), "lo");
        assert_eq!(take_suffix_chars("hello", 0), "");
        assert_eq!(take_suffix_chars("hi", 5), "hi");
        assert_eq!(take_suffix_chars("", 3), "");
    }

    #[test]
    fn take_suffix_chars_unicode() {
        // 中文字符按标量值计数
        assert_eq!(take_suffix_chars("你好世界", 2), "世界");
    }
}
