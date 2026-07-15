//! C ABI 绑定：所有 unsafe 集中于此。返回值均为 JSON 字符串，
//! 调用方通过 `aether_free_string` 释放。错误时返回空指针。

#![allow(unsafe_code)]

use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};

use aether_core::{
    chunk_document, cosine_similarity_f32, cosine_similarity_f64, estimate_tokens, extract_content,
    parse_chunk, parse_with_tool_accumulation, ratelimit::TokenBucket, redact, sha256_hex,
    top_k_f32, AccumulatedToolCall, ParsedChunk, Sha256,
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

// ===== Token 计数 C ABI =====

/// 粗略估算字符串的 token 数（与 Swift `String.estimatedTokens` 算法一致）。
/// 空指针返回 0。
/// # Safety
/// `s` 必须是合法 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn aether_estimate_tokens(s: *const c_char) -> usize {
    if s.is_null() {
        return 0;
    }
    let s = match CStr::from_ptr(s).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };
    estimate_tokens(s)
}

// ===== 脱敏 C ABI =====

/// 对输入字符串脱敏（UUID/邮箱/URL/Token/密码字段/路径）。
/// 返回新分配的 NUL 结尾 UTF-8 字符串，调用方需用 `aether_free_string` 释放。
/// 输入空指针返回空串（非空指针，需释放）。
/// # Safety
/// `input` 必须是合法 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn aether_redact(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return to_cstring("");
    }
    let s = match CStr::from_ptr(input).to_str() {
        Ok(s) => s,
        Err(_) => return to_cstring(""),
    };
    let redacted = redact(s);
    to_cstring(&redacted)
}

// ===== 文档分块 C ABI =====

/// 对文档分块，返回 JSON 字符串数组 `["chunk1","chunk2",...]`。
/// `max_chars == 0` 或空文本返回 `[]`。失败返回空指针。
/// 调用方需用 `aether_free_string` 释放返回值。
/// # Safety
/// `input` 必须是合法 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn aether_chunk_document(
    input: *const c_char,
    max_chars: usize,
    overlap_chars: usize,
) -> *mut c_char {
    if input.is_null() {
        return serde_json::to_string::<[String; 0]>(&[])
            .map(|j| to_cstring(&j))
            .unwrap_or(std::ptr::null_mut());
    }
    let s = match CStr::from_ptr(input).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let chunks = chunk_document(s, max_chars, overlap_chars);
    serde_json::to_string(&chunks)
        .map(|j| to_cstring(&j))
        .unwrap_or(std::ptr::null_mut())
}

// ===== SHA-256 C ABI（流式） =====

/// C 侧持有的 SHA-256 哈希器状态（流式 update）。
#[repr(C)]
pub struct AetherSha256 {
    inner: Sha256,
}

/// 创建新的 SHA-256 哈希器。调用方负责通过 `aether_sha256_free` 释放。
#[no_mangle]
pub extern "C" fn aether_sha256_new() -> *mut AetherSha256 {
    Box::into_raw(Box::new(AetherSha256 {
        inner: Sha256::new(),
    }))
}

/// 追加数据到哈希。空指针安全（no-op）。
/// # Safety
/// `state` 来自 `aether_sha256_new`；`data` 指向 `len` 个有效字节。
#[no_mangle]
pub unsafe extern "C" fn aether_sha256_update(
    state: *mut AetherSha256,
    data: *const u8,
    len: usize,
) {
    if state.is_null() || data.is_null() || len == 0 {
        return;
    }
    let state = &mut *state;
    let slice = std::slice::from_raw_parts(data, len);
    state.inner.update(slice);
}

/// 完成哈希，返回小写十六进制字符串（64 字符，NUL 结尾）。
/// 不消费 state，调用方仍需 `aether_sha256_free` 释放。
/// 返回的字符串需用 `aether_free_string` 释放。空指针 state 返回空串。
/// # Safety
/// `state` 来自 `aether_sha256_new`。
#[no_mangle]
pub unsafe extern "C" fn aether_sha256_finalize(state: *mut AetherSha256) -> *mut c_char {
    if state.is_null() {
        return to_cstring("");
    }
    let state = &*state;
    to_cstring(&state.inner.finalize())
}

/// 释放 SHA-256 哈希器。空指针安全。
/// # Safety
/// `state` 来自 `aether_sha256_new`，且只能释放一次。
#[no_mangle]
pub unsafe extern "C" fn aether_sha256_free(state: *mut AetherSha256) {
    if !state.is_null() {
        drop(Box::from_raw(state));
    }
}

/// 一次性计算字节数组的 SHA-256，返回小写 hex 字符串。
/// 调用方需用 `aether_free_string` 释放返回值。空指针返回空串。
/// # Safety
/// `data` 指向 `len` 个有效字节。
#[no_mangle]
pub unsafe extern "C" fn aether_sha256_hex(data: *const u8, len: usize) -> *mut c_char {
    if data.is_null() || len == 0 {
        return to_cstring(&sha256_hex(b""));
    }
    let slice = std::slice::from_raw_parts(data, len);
    to_cstring(&sha256_hex(slice))
}

// ===== 令牌桶限流 C ABI =====

/// C 侧持有的令牌桶限流器状态。
/// 不加 `#[repr(C)]`，cbindgen 生成 opaque typedef（字段含跨 crate 类型）。
pub struct AetherRateLimiter {
    inner: TokenBucket,
}

/// 创建令牌桶限流器。初始令牌数 = 容量（满桶）。
/// 调用方负责通过 `aether_rate_limiter_free` 释放。
/// - `capacity`: 桶容量（最大令牌数）
/// - `refill_rate`: 每秒补充令牌数
/// - `now_ms`: 当前 epoch 毫秒时间戳
#[no_mangle]
pub extern "C" fn aether_rate_limiter_new(
    capacity: f64,
    refill_rate: f64,
    now_ms: u64,
) -> *mut AetherRateLimiter {
    Box::into_raw(Box::new(AetherRateLimiter {
        inner: TokenBucket::new(capacity, refill_rate, now_ms),
    }))
}

/// 尝试获取 `n` 个令牌。
/// 成功返回 0，失败返回正数（距下次有足够令牌的预估等待秒数）。
/// # Safety
/// `state` 来自 `aether_rate_limiter_new`。
#[no_mangle]
pub unsafe extern "C" fn aether_rate_limiter_acquire(
    state: *mut AetherRateLimiter,
    n: f64,
    now_ms: u64,
) -> f64 {
    if state.is_null() {
        return 1.0;
    }
    let state = &mut *state;
    match state.inner.acquire(n, now_ms) {
        Ok(()) => 0.0,
        Err(retry_after) => retry_after,
    }
}

/// 当前可用令牌数（触发补充后）。
/// # Safety
/// `state` 来自 `aether_rate_limiter_new`。
#[no_mangle]
pub unsafe extern "C" fn aether_rate_limiter_available(
    state: *mut AetherRateLimiter,
    now_ms: u64,
) -> f64 {
    if state.is_null() {
        return 0.0;
    }
    let state = &mut *state;
    state.inner.available_tokens(now_ms)
}

/// 重置桶到满容量。
/// # Safety
/// `state` 来自 `aether_rate_limiter_new`。
#[no_mangle]
pub unsafe extern "C" fn aether_rate_limiter_reset(state: *mut AetherRateLimiter, now_ms: u64) {
    if state.is_null() {
        return;
    }
    let state = &mut *state;
    state.inner.reset(now_ms);
}

/// 释放令牌桶限流器。空指针安全。
/// # Safety
/// `state` 来自 `aether_rate_limiter_new`，且只能释放一次。
#[no_mangle]
pub unsafe extern "C" fn aether_rate_limiter_free(state: *mut AetherRateLimiter) {
    if !state.is_null() {
        drop(Box::from_raw(state));
    }
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
