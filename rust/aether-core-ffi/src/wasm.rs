//! Cloudflare Workers 用的 wasm-bindgen 绑定。
use wasm_bindgen::prelude::*;

use aether_core::{parse_chunk, parse_with_tool_accumulation, AccumulatedToolCall, ParsedChunk};
use std::collections::BTreeMap;

#[wasm_bindgen]
pub struct SseState {
    inner: BTreeMap<i64, AccumulatedToolCall>,
}

/// 序列化视图：与 C ABI（lib.rs `to_parsed_chunk_json`）保持一致，
/// `kind` → `type`，`tool_calls` → `toolCalls`，确保 4 端字段名统一。
#[derive(serde::Serialize)]
struct ViewTool<'a> {
    id: &'a str,
    #[serde(rename = "type")]
    kind: &'a str,
    name: &'a str,
    arguments: &'a str,
}

#[derive(serde::Serialize)]
struct View<'a> {
    content: &'a Option<String>,
    #[serde(rename = "toolCalls")]
    tool_calls: Vec<ViewTool<'a>>,
}

impl<'a> From<&'a ParsedChunk> for View<'a> {
    fn from(p: &'a ParsedChunk) -> Self {
        let tool_calls = p
            .tool_calls
            .as_ref()
            .map(|v| {
                v.iter()
                    .map(|t| ViewTool {
                        id: &t.id,
                        kind: &t.kind,
                        name: &t.name,
                        arguments: &t.arguments,
                    })
                    .collect()
            })
            .unwrap_or_default();
        View {
            content: &p.content,
            tool_calls,
        }
    }
}

#[wasm_bindgen]
#[allow(non_snake_case)]
impl SseState {
    #[wasm_bindgen(constructor)]
    pub fn new() -> SseState {
        SseState {
            inner: BTreeMap::new(),
        }
    }

    /// 返回 content（Workers `parseSSEEvent` 语义）。无 content 返回 null。
    pub fn extractContent(&self, line: &str) -> Option<String> {
        aether_core::extract_content(line)
    }

    /// 返回 content JSON 串（`null` / `"..."`）。非 data 行返回 null。
    pub fn parseChunk(&self, line: &str) -> Option<String> {
        parse_chunk(line).map(|opt| match opt {
            None => "null".to_string(),
            Some(s) => serde_json::to_string(&s).unwrap_or_else(|_| "null".to_string()),
        })
    }

    /// 带 tool_calls 累积，返回 ParsedChunk JSON 串（camelCase 字段，`type` 而非 `kind`）。
    pub fn parseWithTools(&mut self, line: &str) -> Option<String> {
        parse_with_tool_accumulation(line, &mut self.inner)
            .and_then(|p| serde_json::to_string(&View::from(&p)).ok())
    }
}

/// 向量数学：cosine 相似度与 top-K 检索（Workers 端 rag.js 用）。
#[wasm_bindgen]
#[allow(non_snake_case)]
pub struct VectorMath;

#[wasm_bindgen]
#[allow(non_snake_case)]
impl VectorMath {
    /// f32 余弦相似度。长度不等或空返回 0。
    pub fn cosineF32(a: &[f32], b: &[f32]) -> f32 {
        aether_core::cosine_similarity_f32(a, b)
    }

    /// f64 余弦相似度。长度不等或空返回 0。
    pub fn cosineF64(a: &[f64], b: &[f64]) -> f64 {
        aether_core::cosine_similarity_f64(a, b)
    }

    /// top-K 检索。返回 JSON：`[[index,score],...]`（降序）。
    /// `corpus_json` 为 number[][] 的 JSON 字符串（裸数组），`query` 为 Float32Array/number[]。
    pub fn topKF32(query: &[f32], corpus_json: &str, k: usize) -> Option<String> {
        // 直接反序列化裸数组 number[][]（不包裹在对象中）
        let corpus: Vec<Vec<f32>> = serde_json::from_str(corpus_json).ok()?;
        let refs: Vec<&[f32]> = corpus.iter().map(|s| s.as_slice()).collect();
        let result = aether_core::top_k_f32(query, &refs, k);
        serde_json::to_string(
            &result
                .iter()
                .map(|(i, s)| (*i as u64, *s))
                .collect::<Vec<_>>(),
        )
        .ok()
    }
}

/// Token 计数（Workers 端 rag.js 分块 / 上下文窗口管理用）。
#[wasm_bindgen]
#[allow(non_snake_case)]
pub struct TokenCounter;

#[wasm_bindgen]
#[allow(non_snake_case)]
impl TokenCounter {
    /// 粗略估算字符串的 token 数（与 Swift `String.estimatedTokens` 算法一致）。
    pub fn estimateTokens(s: &str) -> usize {
        aether_core::estimate_tokens(s)
    }
}

/// 脱敏器（Workers 端 chat.js 用户消息 / 错误信息脱敏用）。
#[wasm_bindgen]
#[allow(non_snake_case)]
pub struct Redactor;

#[wasm_bindgen]
#[allow(non_snake_case)]
impl Redactor {
    /// 对输入字符串脱敏（UUID/邮箱/URL/Token/密码字段/路径）。
    /// 返回脱敏后的新字符串，原字符串不变。
    pub fn redact(s: &str) -> String {
        aether_core::redact(s)
    }
}

/// 文档分块器（Workers 端 rag.js 文档索引用）。
#[wasm_bindgen]
#[allow(non_snake_case)]
pub struct Chunker;

#[wasm_bindgen]
#[allow(non_snake_case)]
impl Chunker {
    /// 对文档分块，返回 JSON 字符串数组 `["chunk1","chunk2",...]`。
    /// 按 UAX #29 句子边界切分，累积到 `max_chars` 后落盘，
    /// 相邻块用 `overlap_chars` 个字符拼接保证上下文连续。
    pub fn chunkDocument(text: &str, maxChars: usize, overlapChars: usize) -> String {
        let chunks = aether_core::chunk_document(text, maxChars, overlapChars);
        serde_json::to_string(&chunks).unwrap_or_else(|_| "[]".to_string())
    }
}
