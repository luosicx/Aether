//! SSE 流解析器：统一 Swift / Workers / Android 的解析行为。
//!
//! 与 Swift `SSEParser` 对齐：
//! - 跳过非 `data:` 前缀行（返回 None 表示"非 data 行"）
//! - `[DONE]` 在 `parse_chunk` 中返回 `Some(None)`（命中 data 行但无 payload）
//! - JSON 解析失败返回 None（保持与 `try? JSONDecoder().decode` 一致）
//! - tool_calls 按 index 跨 chunk 累积 arguments

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Deserialize)]
struct ChatChunk {
    choices: Option<Vec<Choice>>,
}

#[derive(Debug, Deserialize)]
struct Choice {
    delta: Option<Delta>,
}

#[derive(Debug, Deserialize)]
struct Delta {
    content: Option<String>,
    tool_calls: Option<Vec<ToolCallDelta>>,
}

#[derive(Debug, Deserialize)]
struct ToolCallDelta {
    index: Option<i64>,
    id: Option<String>,
    #[serde(rename = "type")]
    kind: Option<String>,
    function: Option<FunctionBlock>,
}

#[derive(Debug, Deserialize)]
struct FunctionBlock {
    name: Option<String>,
    arguments: Option<String>,
}

/// 跨 chunk 累积后的工具调用（公开，FFI 需要导出）。
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AccumulatedToolCall {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub arguments: String,
}

/// 单次解析产物（公开）。
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ParsedChunk {
    pub content: Option<String>,
    pub tool_calls: Option<Vec<AccumulatedToolCall>>,
}

/// Workers `parseSSEEvent` 语义：返回 content 字符串。
/// 非 data 行 / [DONE] / 无 content / 空 content 返回 None。
pub fn extract_content(line: &str) -> Option<String> {
    let data = strip_data_prefix(line)?;
    if data == "[DONE]" {
        return None;
    }
    let chunk: ChatChunk = serde_json::from_str(&data).ok()?;
    chunk
        .choices
        .and_then(|mut c| c.pop())
        .and_then(|c| c.delta)
        .and_then(|d| d.content)
        .filter(|s| !s.is_empty())
}

/// Swift `parseChunk` 等价物。
/// 返回值语义：
/// - `None`：非 data 行 / JSON 解析失败
/// - `Some(None)`：`data: [DONE]`
/// - `Some(Some(s))`：有 content（可能为空串）
pub fn parse_chunk(line: &str) -> Option<Option<String>> {
    let data = strip_data_prefix(line)?;
    if data == "[DONE]" {
        return Some(None);
    }
    let chunk: ChatChunk = serde_json::from_str(&data).ok()?;
    let content = chunk
        .choices
        .and_then(|mut c| c.pop())
        .and_then(|c| c.delta)
        .and_then(|d| d.content);
    Some(content)
}

/// Swift `parseWithToolAccumulation` 等价物。
/// `accumulated` 由调用方持有跨调用复用。返回 None 表示该行非 data 行/[DONE]/解析失败。
pub fn parse_with_tool_accumulation(
    line: &str,
    accumulated: &mut BTreeMap<i64, AccumulatedToolCall>,
) -> Option<ParsedChunk> {
    let content_opt = parse_chunk(line)?;
    let data = strip_data_prefix(line)?;
    let chunk: ChatChunk = serde_json::from_str(&data).ok()?;
    let deltas = chunk
        .choices
        .and_then(|mut c| c.pop())
        .and_then(|c| c.delta)
        .and_then(|d| d.tool_calls);

    if let Some(deltas) = deltas {
        for td in deltas {
            let idx = td.index.unwrap_or(0);
            match accumulated.get_mut(&idx) {
                Some(existing) => {
                    if let Some(args) = td.function.as_ref().and_then(|f| f.arguments.as_deref()) {
                        existing.arguments.push_str(args);
                    }
                }
                None => {
                    // 与 Swift `guard let id = td.id, let name = ... else { continue }` 对齐：
                    // 缺少 id 或 name 时跳过该 delta（continue），而非用 `?` 中断整行解析，
                    // 否则会丢弃同一行已提取的 content（数据丢失回归）。
                    let id = match td.id {
                        Some(id) => id,
                        None => continue,
                    };
                    let name = match td.function.as_ref().and_then(|f| f.name.clone()) {
                        Some(name) => name,
                        None => continue,
                    };
                    let kind = td.kind.unwrap_or_else(|| "function".to_string());
                    let arguments = td
                        .function
                        .as_ref()
                        .and_then(|f| f.arguments.clone())
                        .unwrap_or_default();
                    accumulated.insert(
                        idx,
                        AccumulatedToolCall {
                            id,
                            kind,
                            name,
                            arguments,
                        },
                    );
                }
            }
        }
    }

    let tool_calls = if accumulated.is_empty() {
        None
    } else {
        let mut v: Vec<_> = accumulated.values().cloned().collect();
        v.sort_by(|a, b| a.id.cmp(&b.id));
        Some(v)
    };
    Some(ParsedChunk {
        content: content_opt,
        tool_calls,
    })
}

fn strip_data_prefix(line: &str) -> Option<String> {
    let trimmed = line.trim_start();
    let rest = trimmed.strip_prefix("data:")?;
    Some(rest.trim_start().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skips_non_data_lines() {
        assert_eq!(parse_chunk(": keepalive"), None);
        assert_eq!(parse_chunk("event: ping"), None);
    }

    #[test]
    fn done_returns_some_none() {
        assert_eq!(parse_chunk("data: [DONE]"), Some(None));
    }

    #[test]
    fn extracts_content() {
        let line = r#"data: {"choices":[{"delta":{"content":"Hi"}}]}"#;
        assert_eq!(extract_content(line), Some("Hi".to_string()));
        assert_eq!(parse_chunk(line), Some(Some("Hi".to_string())));
    }

    #[test]
    fn empty_content_yields_none_in_extract() {
        let line = r#"data: {"choices":[{"delta":{"content":""}}]}"#;
        assert_eq!(extract_content(line), None);
        assert_eq!(parse_chunk(line), Some(Some("".to_string())));
    }

    #[test]
    fn malformed_json_returns_none() {
        assert_eq!(parse_chunk("data: {not json"), None);
    }

    #[test]
    fn accumulates_tool_calls_across_chunks() {
        let mut acc: BTreeMap<i64, AccumulatedToolCall> = BTreeMap::new();
        // 第一片：声明工具 0
        let first = r#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}"#;
        let r1 = parse_with_tool_accumulation(first, &mut acc).unwrap();
        assert_eq!(r1.content, None);
        let tc = r1.tool_calls.as_ref().unwrap();
        assert_eq!(tc.len(), 1);
        assert_eq!(tc[0].name, "get_weather");
        assert_eq!(tc[0].arguments, "");
        // 第二片：仅追加 arguments（JSON 值为 {"city": 经拼接后为该串）
        let second = r#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":"}}]}}]}"#;
        let r2 = parse_with_tool_accumulation(second, &mut acc).unwrap();
        assert_eq!(r2.content, None);
        let tc2 = r2.tool_calls.as_ref().unwrap();
        assert_eq!(tc2[0].arguments, r#"{"city":"#);
        // 第三片：content 与 arguments 同时
        let third = r#"data: {"choices":[{"delta":{"content":"ok","tool_calls":[{"index":0,"function":{"arguments":"\"BJ\"}"}}]}}]}"#;
        let r3 = parse_with_tool_accumulation(third, &mut acc).unwrap();
        assert_eq!(r3.content.as_deref(), Some("ok"));
        assert_eq!(
            r3.tool_calls.as_ref().unwrap()[0].arguments,
            r#"{"city":"BJ"}"#
        );
    }

    #[test]
    fn tool_calls_sorted_by_id() {
        let mut acc: BTreeMap<i64, AccumulatedToolCall> = BTreeMap::new();
        let a = r#"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","type":"function","function":{"name":"b","arguments":""}}]}}]}"#;
        let b = r#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","type":"function","function":{"name":"a","arguments":""}}]}}]}"#;
        parse_with_tool_accumulation(a, &mut acc);
        parse_with_tool_accumulation(b, &mut acc);
        let tc = parse_with_tool_accumulation(b, &mut acc)
            .unwrap()
            .tool_calls
            .unwrap();
        assert_eq!(tc[0].id, "a");
        assert_eq!(tc[1].id, "b");
    }

    /// 回归测试：新 tool_call delta 缺少 id 时不应丢弃同一行的 content。
    /// 修复前：`td.id?` 中断整行 → 返回 None → content 丢失。
    /// 修复后：跳过该 delta（continue），content 正常返回。
    #[test]
    fn new_tool_call_without_id_preserves_content() {
        let mut acc: BTreeMap<i64, AccumulatedToolCall> = BTreeMap::new();
        // content + 新 tool_call（index=0 未见过）但无 id
        let line = r#"data: {"choices":[{"delta":{"content":"important text","tool_calls":[{"index":0,"type":"function","function":{"name":"fn","arguments":""}}]}}]}"#;
        let result = parse_with_tool_accumulation(line, &mut acc).unwrap();
        // content 不应丢失
        assert_eq!(result.content.as_deref(), Some("important text"));
        // 缺少 id 的 tool_call 被跳过，accumulated 仍为空
        assert!(acc.is_empty());
        assert!(result.tool_calls.is_none());
    }

    /// 回归测试：新 tool_call delta 缺少 function.name 时不应丢弃同一行的 content。
    #[test]
    fn new_tool_call_without_name_preserves_content() {
        let mut acc: BTreeMap<i64, AccumulatedToolCall> = BTreeMap::new();
        let line = r#"data: {"choices":[{"delta":{"content":"keep me","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"arguments":""}}]}}]}"#;
        let result = parse_with_tool_accumulation(line, &mut acc).unwrap();
        assert_eq!(result.content.as_deref(), Some("keep me"));
        assert!(acc.is_empty());
    }
}
