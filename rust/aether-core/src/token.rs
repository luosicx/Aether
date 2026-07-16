//! Token 计数：粗估公式（与 Swift `String.estimatedTokens` 算法一致）。
//!
//! 算法：英文按空格分词数 × 1.3 + 非 ASCII 字符数 × 1.5，向零截断取整。
//! 用于上下文窗口管理与发送前截断。
//!
//! 后续可替换为 `tiktoken-rs` 精确 BPE（误差从 ~30% 降至 ~0），
//! 本模块的公开签名 `estimate_tokens` 保持不变，调用方无感升级。

/// 粗略估算字符串的 token 数。
///
/// 算法细节（与 Swift `String.estimatedTokens` 完全一致）：
/// - 按空格 `' '` 分词（折叠连续空格），词数 × 1.3
/// - 非 ASCII 字符（中日韩等）每字 × 1.5
/// - 两者相加后向零截断取整（等同 floor 对正数）
pub fn estimate_tokens(s: &str) -> usize {
    // Swift `split(separator: " ", omittingEmptySubsequences: true)` 等价：
    // 按 ' ' 切分后过滤空片段（折叠连续空格）。
    let ascii_words = s.split(' ').filter(|part| !part.is_empty()).count();
    let non_ascii_count = s.chars().filter(|c| !c.is_ascii()).count();
    let ascii_token_estimate = ascii_words as f64 * 1.3;
    let non_ascii_token_estimate = non_ascii_count as f64 * 1.5;
    // Swift `Int(Double)` 对正数等同 floor；Rust `as usize` 对正数也等同 floor。
    (ascii_token_estimate + non_ascii_token_estimate) as usize
}

#[cfg(test)]
mod tests {
    use super::*;

    // 测试期望与 Swift `StringTokenCountTests.swift` 表驱动用例完全一致，
    // 确保 Rust 实现与 Swift 兜底实现输出相同（可互换）。

    #[test]
    fn empty_string() {
        assert_eq!(estimate_tokens(""), 0);
    }

    #[test]
    fn single_english_word() {
        // 1 词 → Int(1.3) = 1
        assert_eq!(estimate_tokens("hello"), 1);
    }

    #[test]
    fn two_english_words() {
        // 2 词 → Int(2.6) = 2
        assert_eq!(estimate_tokens("hello world"), 2);
    }

    #[test]
    fn consecutive_spaces_collapsed() {
        // 连续空格 split 折叠 → 2 词（与 Swift omittingEmptySubsequences 一致）
        assert_eq!(estimate_tokens("hello  world"), 2);
    }

    #[test]
    fn pure_chinese() {
        // 1 词 Int(1.3) + 4 非 ASCII 字 Int(4*1.5) = 1 + 6 = 7
        assert_eq!(estimate_tokens("你好世界"), 7);
    }

    #[test]
    fn four_english_words() {
        // 4 词 → Int(4 * 1.3 = 5.2) = 5
        assert_eq!(estimate_tokens("hello world foo bar"), 5);
    }

    #[test]
    fn mixed_chinese_english() {
        // 2 英文词 Int(2*1.3) + 2 中文字 Int(2*1.5) = 2 + 3 = 5
        assert_eq!(estimate_tokens("hello 你好"), 5);
    }

    #[test]
    fn tab_is_non_ascii_split_preserves() {
        // 制表符非空格，不分割；但 tab 是 ASCII（0x09），不计入 non_ascii
        // "a\tb" → 1 词（无空格）+ 0 非 ASCII → Int(1.3) = 1
        assert_eq!(estimate_tokens("a\tb"), 1);
    }

    #[test]
    fn leading_trailing_spaces() {
        // " hello " → split 后 ["", "hello", ""] → 过滤空 → 1 词
        assert_eq!(estimate_tokens(" hello "), 1);
    }
}
