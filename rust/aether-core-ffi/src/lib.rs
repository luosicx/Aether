//! C ABI 绑定：所有 unsafe 集中于此。返回值均为 JSON 字符串，
//! 调用方通过 `aether_free_string` 释放。错误时返回空指针。

#![allow(unsafe_code)]

use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};

use aether_core::{
    cosine_similarity_f32, cosine_similarity_f64, extract_content, parse_chunk,
    parse_with_tool_accumulation, top_k_f32, AccumulatedToolCall, ParsedChunk,
};

/// C 侧持有的解析器状态（跨调用累积 tool_calls）。
#[repr(C)]
pub struct AetherSseState {
    inner: BTreeMap<i64, AccumulatedToolCall>,
}

#[no_mangle]
pub extern "C" fn aether_sse_state_new() -> *mut AetherSseState {
    Box::into_raw(Box::new(AetherSseState {
        inner: BTreeMap::new(),
    }))
}

/// # Safety
/// `state` 必须由 `aether_sse_state_new` 返回，且未被释放。
#[no_mangle]
pub unsafe extern "C" fn aether_sse_state_free(state: *mut AetherSseState) {
    if !state.is_null() {
        drop(Box::from_raw(state));
    }
}

/// 解析单行，返回 content 的 JSON 串（`null` / `"..."`）。
/// 非 data 行 / 解析失败返回空指针。
/// # Safety
/// `line` 必须是合法 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn aether_sse_parse_chunk(line: *const c_char) -> *mut c_char {
    if line.is_null() {
        return std::ptr::null_mut();
    }
    let line = match CStr::from_ptr(line).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    match parse_chunk(line) {
        None => std::ptr::null_mut(),
        Some(None) => to_cstring("null"),
        Some(Some(s)) => serde_json::to_string(&s)
            .map(|j| to_cstring(&j))
            .unwrap_or(std::ptr::null_mut()),
    }
}

/// Workers 等价的 content 提取。
/// # Safety
/// `line` 必须是合法 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn aether_sse_extract_content(line: *const c_char) -> *mut c_char {
    if line.is_null() {
        return std::ptr::null_mut();
    }
    let line = match CStr::from_ptr(line).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    match extract_content(line) {
        Some(s) => serde_json::to_string(&s)
            .map(|j| to_cstring(&j))
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

/// 带 tool_calls 累积的解析，返回 `ParsedChunk` 的 JSON 串。
/// # Safety
/// `line` 合法 UTF-8；`state` 来自 `aether_sse_state_new`。
#[no_mangle]
pub unsafe extern "C" fn aether_sse_parse_with_tools(
    line: *const c_char,
    state: *mut AetherSseState,
) -> *mut c_char {
    if line.is_null() || state.is_null() {
        return std::ptr::null_mut();
    }
    let line = match CStr::from_ptr(line).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let state = &mut *state;
    match parse_with_tool_accumulation(line, &mut state.inner) {
        Some(p) => to_parsed_chunk_json(&p),
        None => std::ptr::null_mut(),
    }
}

/// 释放由上述函数返回的字符串。空指针安全。
/// # Safety
/// `ptr` 必须由本 crate 的返回值产生，且只能释放一次。
#[no_mangle]
pub unsafe extern "C" fn aether_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// 释放通用 void*（预留）。
/// # Safety
/// `ptr` 必须由本 crate 产生，且只能释放一次。
#[no_mangle]
pub unsafe extern "C" fn aether_free(ptr: *mut c_void) {
    if !ptr.is_null() {
        drop(Box::from_raw(ptr as *mut u8));
    }
}

fn to_cstring(s: &str) -> *mut c_char {
    CString::new(s)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

// ===== 向量数学 C ABI =====
//
// cosine 直接返回标量（无分配）；top_k 因 corpus 为变长二维数组，用 JSON 进出。

/// f32 余弦相似度。空指针或长度不等返回 0。
/// # Safety
/// `a`/`b` 必须指向至少 `a_len`/`b_len` 个有效 f32。
#[no_mangle]
pub unsafe extern "C" fn aether_cosine_f32(
    a: *const f32,
    a_len: usize,
    b: *const f32,
    b_len: usize,
) -> f32 {
    if a.is_null() || b.is_null() {
        return 0.0;
    }
    let a = std::slice::from_raw_parts(a, a_len);
    let b = std::slice::from_raw_parts(b, b_len);
    cosine_similarity_f32(a, b)
}

/// f64 余弦相似度。空指针或长度不等返回 0。
/// # Safety
/// `a`/`b` 必须指向至少 `a_len`/`b_len` 个有效 f64。
#[no_mangle]
pub unsafe extern "C" fn aether_cosine_f64(
    a: *const f64,
    a_len: usize,
    b: *const f64,
    b_len: usize,
) -> f64 {
    if a.is_null() || b.is_null() {
        return 0.0;
    }
    let a = std::slice::from_raw_parts(a, a_len);
    let b = std::slice::from_raw_parts(b, b_len);
    cosine_similarity_f64(a, b)
}

/// top-K 检索（f32）。输入 JSON：`{"query":[...],"corpus":[[...],[...]],"k":5}`；
/// 输出 JSON：`[[index,score],...]`（降序）。失败返回空指针。
/// # Safety
/// `input` 必须是合法 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn aether_top_k_f32_json(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return std::ptr::null_mut();
    }
    let input = match CStr::from_ptr(input).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    #[derive(serde::Deserialize)]
    struct In {
        query: Vec<f32>,
        corpus: Vec<Vec<f32>>,
        k: usize,
    }
    let parsed: In = match serde_json::from_str(input) {
        Ok(v) => v,
        Err(_) => return std::ptr::null_mut(),
    };
    let corpus_refs: Vec<&[f32]> = parsed.corpus.iter().map(|s| s.as_slice()).collect();
    let result = top_k_f32(&parsed.query, &corpus_refs, parsed.k);
    // 序列化为 [[index, score], ...]
    serde_json::to_string(
        &result
            .iter()
            .map(|(i, s)| (*i as u64, *s))
            .collect::<Vec<_>>(),
    )
    .map(|j| to_cstring(&j))
    .unwrap_or(std::ptr::null_mut())
}

/// FFI 友好的序列化视图：字段名统一 camelCase，`kind`→`type` 与 Swift 对齐。
fn to_parsed_chunk_json(p: &ParsedChunk) -> *mut c_char {
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
    let tools: Vec<ViewTool> = p
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
    let view = View {
        content: &p.content,
        tool_calls: tools,
    };
    serde_json::to_string(&view)
        .map(|j| to_cstring(&j))
        .unwrap_or(std::ptr::null_mut())
}

#[cfg(target_arch = "wasm32")]
mod wasm;

#[cfg(target_os = "android")]
mod jni;
