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
