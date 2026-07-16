//! 向量数学：余弦相似度 / top-K 检索。
//!
//! 统一 4 端（Swift SemanticCache / RAGService / MemoryService / CloudflareWorkers）
//! 此前各自重复实现的 cosine 计算，并移出 @MainActor 阻塞主线程。
//!
//! 边界约定（与既有 Swift 实现一致）：
//! - 长度不等 → 返回 0
//! - 空向量 → 返回 0
//! - 零范数向量（全零）→ 返回 0（避免除零）

/// f32 余弦相似度（SemanticCache / RAGService 用）。
pub fn cosine_similarity_f32(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }
    let mut dot = 0.0f32;
    let mut norm_a = 0.0f32;
    let mut norm_b = 0.0f32;
    for i in 0..a.len() {
        let av = a[i];
        let bv = b[i];
        dot += av * bv;
        norm_a += av * av;
        norm_b += bv * bv;
    }
    if norm_a <= 0.0 || norm_b <= 0.0 {
        return 0.0;
    }
    dot / (norm_a.sqrt() * norm_b.sqrt())
}

/// f64 余弦相似度（MemoryService 用，因 Memory.embedding: [Double]）。
pub fn cosine_similarity_f64(a: &[f64], b: &[f64]) -> f64 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }
    let mut dot = 0.0f64;
    let mut norm_a = 0.0f64;
    let mut norm_b = 0.0f64;
    for i in 0..a.len() {
        let av = a[i];
        let bv = b[i];
        dot += av * bv;
        norm_a += av * av;
        norm_b += bv * bv;
    }
    if norm_a <= 0.0 || norm_b <= 0.0 {
        return 0.0;
    }
    dot / (norm_a.sqrt() * norm_b.sqrt())
}

/// top-K 检索：在 corpus 中找出与 query 余弦相似度最高的 K 项。
///
/// 返回 `(index, score)` 元组数组，按 score 降序排列，长度 ≤ k。
/// corpus 中长度不匹配或零范数的项得分为 0，仍参与排序（与既有 Swift 行为一致）。
pub fn top_k_f32(query: &[f32], corpus: &[&[f32]], k: usize) -> Vec<(usize, f32)> {
    if k == 0 {
        return Vec::new();
    }
    let mut scored: Vec<(usize, f32)> = corpus
        .iter()
        .enumerate()
        .map(|(i, doc)| (i, cosine_similarity_f32(query, doc)))
        .collect();
    // 降序排序：score 高者优先；score 相同则 index 小者优先（稳定）
    scored.sort_by(|a, b| {
        b.1.partial_cmp(&a.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.0.cmp(&b.0))
    });
    scored.truncate(k);
    scored
}

#[cfg(test)]
mod tests {
    use super::*;

    const EPS: f32 = 1e-5;

    #[test]
    fn identical_vectors_have_cosine_one() {
        let a = [1.0_f32, 2.0, 3.0];
        assert!((cosine_similarity_f32(&a, &a) - 1.0).abs() < EPS);
        let b = [0.1_f64, 0.2, 0.3];
        assert!((cosine_similarity_f64(&b, &b) - 1.0).abs() < 1e-10);
    }

    #[test]
    fn orthogonal_vectors_have_cosine_zero() {
        let a = [1.0_f32, 0.0];
        let b = [0.0_f32, 1.0];
        assert!(cosine_similarity_f32(&a, &b).abs() < EPS);
    }

    #[test]
    fn opposite_vectors_have_cosine_minus_one() {
        let a = [1.0_f32, 2.0, 3.0];
        let b = [-1.0_f32, -2.0, -3.0];
        assert!((cosine_similarity_f32(&a, &b) + 1.0).abs() < EPS);
    }

    #[test]
    fn mismatched_length_returns_zero() {
        let a = [1.0_f32, 2.0, 3.0];
        let b = [1.0_f32, 2.0];
        assert_eq!(cosine_similarity_f32(&a, &b), 0.0);
    }

    #[test]
    fn empty_vectors_return_zero() {
        let a: [f32; 0] = [];
        let b: [f32; 0] = [];
        assert_eq!(cosine_similarity_f32(&a, &b), 0.0);
        let c: [f64; 0] = [];
        assert_eq!(cosine_similarity_f64(&c, &c), 0.0);
    }

    #[test]
    fn zero_norm_vectors_return_zero() {
        let a = [0.0_f32, 0.0, 0.0];
        let b = [1.0_f32, 2.0, 3.0];
        assert_eq!(cosine_similarity_f32(&a, &b), 0.0);
    }

    #[test]
    fn f64_matches_known_value() {
        // 已知: a=[1,0,0], b=[1,1,0] → cosine = 1/√2 ≈ 0.7071
        let a = [1.0_f64, 0.0, 0.0];
        let b = [1.0_f64, 1.0, 0.0];
        let result = cosine_similarity_f64(&a, &b);
        assert!((result - std::f64::consts::FRAC_1_SQRT_2).abs() < 1e-10);
    }

    #[test]
    fn top_k_returns_descending() {
        let query = [1.0_f32, 0.0];
        let corpus: Vec<&[f32]> = vec![&[0.0, 1.0], &[1.0, 0.0], &[1.0, 1.0]];
        let result = top_k_f32(&query, &corpus, 2);
        // [1,0] 与 query 完全相同 → 1.0；[1,1] → 1/√2 ≈ 0.707；[0,1] → 0
        assert_eq!(result.len(), 2);
        assert_eq!(result[0].0, 1); // index 1, score 1.0
        assert!((result[0].1 - 1.0).abs() < EPS);
        assert_eq!(result[1].0, 2); // index 2, score ≈ 0.707
    }

    #[test]
    fn top_k_with_k_zero_returns_empty() {
        let query = [1.0_f32];
        let corpus: Vec<&[f32]> = vec![&[1.0]];
        assert!(top_k_f32(&query, &corpus, 0).is_empty());
    }

    #[test]
    fn top_k_truncates_when_k_exceeds_corpus() {
        let query = [1.0_f32];
        let corpus: Vec<&[f32]> = vec![&[1.0], &[0.5]];
        let result = top_k_f32(&query, &corpus, 10);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn top_k_handles_mismatched_lengths() {
        let query = [1.0_f32, 2.0, 3.0];
        let corpus: Vec<&[f32]> = vec![&[1.0, 2.0], &[1.0, 2.0, 3.0]];
        let result = top_k_f32(&query, &corpus, 2);
        // index 0 长度不匹配 → 0；index 1 完全相同 → 1.0
        assert_eq!(result[0].0, 1);
        assert!((result[0].1 - 1.0).abs() < EPS);
    }
}
