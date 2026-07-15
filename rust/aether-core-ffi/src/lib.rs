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
// 不加 `#[repr(C)]`：字段类型 `BTreeMap` 跨 crate 无法布局，
// cbindgen 生成 opaque typedef（与 AetherInferenceEngine 等一致），
// 跨 FFI 仅以 `*mut AetherSseState` 传递，不需要 C 布局。
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
// 不加 `#[repr(C)]`：字段类型 `Sha256` 跨 crate 无法布局，
// cbindgen 生成 opaque typedef，跨 FFI 仅以 `*mut AetherSha256` 传递。
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

// ===== 插件沙箱 C ABI（仅 host target，wasm32 不编译） =====
//
// 对应原 `PluginSandbox.swift`（声明式伪沙箱 → wasmtime 真隔离）。
// 三层 opaque 句柄：AetherSandbox（引擎）/ AetherSandboxModule（编译产物）/
// AetherSandboxInstance（运行时实例）。

#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
use aether_core::sandbox::{Sandbox, SandboxError, SandboxInstance, SandboxModule};

/// C 侧持有的沙箱引擎。opaque（字段含跨 crate 类型，cbindgen 生成 opaque typedef）。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
pub struct AetherSandbox {
    inner: Sandbox,
}

/// C 侧持有的已加载模块。opaque。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
pub struct AetherSandboxModule {
    inner: SandboxModule,
}

/// C 侧持有的沙箱实例。opaque。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
pub struct AetherSandboxInstance {
    inner: SandboxInstance,
}

/// 创建沙箱引擎。Pulley 解释器（无 JIT），iOS 友好。
///
/// - `max_fuel`: CPU 指令限额（30 秒 ≈ 30_000_000_000）
/// - `max_memory_bytes`: 线性内存上限（字节，50 MB = 52_428_800）
///
/// 失败返回空指针。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub extern "C" fn aether_sandbox_new(max_fuel: u64, max_memory_bytes: usize) -> *mut AetherSandbox {
    use aether_core::sandbox::SandboxConfig;
    let config = SandboxConfig {
        max_fuel,
        max_memory_bytes,
    };
    match Sandbox::new(config) {
        Ok(s) => Box::into_raw(Box::new(AetherSandbox { inner: s })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 编译 WASM 模块（字节码）。失败返回空指针。
/// # Safety
/// `sandbox` 来自 `aether_sandbox_new`；`wasm` 指向 `wasm_len` 字节。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_load(
    sandbox: *mut AetherSandbox,
    wasm: *const u8,
    wasm_len: usize,
) -> *mut AetherSandboxModule {
    if sandbox.is_null() || wasm.is_null() || wasm_len == 0 {
        return std::ptr::null_mut();
    }
    let sandbox = &*sandbox;
    let bytes = std::slice::from_raw_parts(wasm, wasm_len);
    match sandbox.inner.load(bytes) {
        Ok(m) => Box::into_raw(Box::new(AetherSandboxModule { inner: m })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 实例化模块，返回可调用实例。失败返回空指针。
/// 初始 fuel = 创建引擎时的 max_fuel。
/// # Safety
/// `module` 来自 `aether_sandbox_load`。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_instantiate(
    module: *mut AetherSandboxModule,
) -> *mut AetherSandboxInstance {
    if module.is_null() {
        return std::ptr::null_mut();
    }
    let module = &*module;
    match module.inner.instantiate() {
        Ok(i) => Box::into_raw(Box::new(AetherSandboxInstance { inner: i })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 调用插件的 execute 函数，传入 JSON 参数，返回结果 JSON 字符串。
/// 成功：`{"ok":true,"output":"...","fuelRemaining":N,"outOfFuel":false}`
/// 失败：`{"ok":false,"error":"OutOfFuel|MissingExecute|..."}`
/// 调用方需用 `aether_free_string` 释放返回值。
/// # Safety
/// `instance` 来自 `aether_sandbox_instantiate`；`args_json` 合法 NUL 结尾 UTF-8。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_call_json(
    instance: *mut AetherSandboxInstance,
    args_json: *const c_char,
) -> *mut c_char {
    if instance.is_null() {
        return to_cstring(r#"{"ok":false,"error":"NullInstance"}"#);
    }
    let args = if args_json.is_null() {
        ""
    } else {
        match CStr::from_ptr(args_json).to_str() {
            Ok(s) => s,
            Err(_) => return to_cstring(r#"{"ok":false,"error":"InvalidUtf8"}"#),
        }
    };
    let instance = &mut *instance;
    match instance.inner.call_json(args) {
        Ok(r) => {
            let output_json = serde_json::to_string(&r.output).unwrap_or_else(|_| "null".into());
            let json = format!(
                r#"{{"ok":true,"output":{},"fuelRemaining":{},"outOfFuel":{}}}"#,
                output_json, r.fuel_remaining, r.out_of_fuel
            );
            to_cstring(&json)
        }
        Err(e) => {
            let err_str = match e {
                SandboxError::OutOfFuel => "OutOfFuel",
                SandboxError::MemoryLimit => "MemoryLimit",
                SandboxError::MissingExecute => "MissingExecute",
                SandboxError::MissingMemory => "MissingMemory",
                SandboxError::Compile(_) => "Compile",
                SandboxError::Instantiate(_) => "Instantiate",
                SandboxError::Call(_) => "Call",
                SandboxError::Utf8(_) => "Utf8",
            };
            let json = format!(r#"{{"ok":false,"error":"{}"}}"#, err_str);
            to_cstring(&json)
        }
    }
}

/// 直接调用 execute（数值参数），返回结果。失败返回 0。
/// # Safety
/// `instance` 来自 `aether_sandbox_instantiate`。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_call_raw(
    instance: *mut AetherSandboxInstance,
    arg: i32,
) -> i32 {
    if instance.is_null() {
        return 0;
    }
    let instance = &mut *instance;
    instance.inner.call_raw(arg).unwrap_or(0)
}

/// 剩余 fuel。
/// # Safety
/// `instance` 来自 `aether_sandbox_instantiate`。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_fuel_remaining(
    instance: *mut AetherSandboxInstance,
) -> u64 {
    if instance.is_null() {
        return 0;
    }
    let instance = &*instance;
    instance.inner.fuel_remaining()
}

/// 重置 fuel 到初始值。
/// # Safety
/// `instance` 来自 `aether_sandbox_instantiate`。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_refill_fuel(instance: *mut AetherSandboxInstance) {
    if instance.is_null() {
        return;
    }
    let instance = &mut *instance;
    instance.inner.refill_fuel();
}

/// 释放沙箱引擎。空指针安全。
/// # Safety
/// `sandbox` 来自 `aether_sandbox_new`，且只能释放一次。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_free(sandbox: *mut AetherSandbox) {
    if !sandbox.is_null() {
        drop(Box::from_raw(sandbox));
    }
}

/// 释放已加载模块。空指针安全。
/// # Safety
/// `module` 来自 `aether_sandbox_load`，且只能释放一次。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_module_free(module: *mut AetherSandboxModule) {
    if !module.is_null() {
        drop(Box::from_raw(module));
    }
}

/// 释放沙箱实例。空指针安全。
/// # Safety
/// `instance` 来自 `aether_sandbox_instantiate`，且只能释放一次。
#[cfg(not(any(target_arch = "wasm32", target_os = "ios", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_sandbox_instance_free(instance: *mut AetherSandboxInstance) {
    if !instance.is_null() {
        drop(Box::from_raw(instance));
    }
}

// ===== 端侧推理 C ABI（仅 host target，wasm32 不编译） =====
//
// 对应 `MLXInferenceEngine.swift`（Apple MLX）→ candle 跨端推理。
// 本层负责 unsafe mmap 加载 safetensors，构造 VarBuilder，
// 然后调用 aether-core 的纯逻辑 InferenceEngine::load_from_components。

#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
use aether_core::inference::{InferenceConfig, InferenceEngine, InferenceError};
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
use candle_core::Device;
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
use candle_transformers::models::qwen2::Config as Qwen2Config;

/// C 侧持有的推理引擎。opaque（字段含跨 crate 类型）。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
pub struct AetherInferenceEngine {
    inner: InferenceEngine,
}

/// 创建推理引擎。返回的引擎未加载模型，需调用 `aether_inference_load_model`。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
#[no_mangle]
pub extern "C" fn aether_inference_new() -> *mut AetherInferenceEngine {
    Box::into_raw(Box::new(AetherInferenceEngine {
        inner: InferenceEngine::new(),
    }))
}

/// 加载本地 safetensors 模型目录。
///
/// model_dir 应包含：config.json / tokenizer.json / model.safetensors
///
/// 参数（JSON）：
/// ```json
/// {"temperature":0.7,"maxTokens":1024,"repeatPenalty":1.1,
///  "repeatLastN":64,"topP":0.9,"seed":null,"eosTokenId":null}
/// ```
/// seed / eosTokenId 为 null 时使用默认（seed 随机，eosTokenId 从 config.json 读取）。
///
/// 返回：成功 0，失败返回 1（错误信息通过 aether_inference_last_error 获取）。
/// # Safety
/// `engine` 来自 `aether_inference_new`；`model_dir` 合法 NUL 结尾 UTF-8。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_inference_load_model(
    engine: *mut AetherInferenceEngine,
    model_dir: *const c_char,
    params_json: *const c_char,
) -> i32 {
    if engine.is_null() {
        return 1;
    }
    let dir_str = if model_dir.is_null() {
        return 1;
    } else {
        match CStr::from_ptr(model_dir).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 1,
        }
    };

    let params_str = if params_json.is_null() {
        "{}"
    } else {
        match CStr::from_ptr(params_json).to_str() {
            Ok(s) => s,
            Err(_) => return 1,
        }
    };

    #[derive(serde::Deserialize)]
    struct Params {
        temperature: Option<f64>,
        max_tokens: Option<usize>,
        repeat_penalty: Option<f32>,
        repeat_last_n: Option<usize>,
        top_p: Option<f64>,
        seed: Option<u64>,
        eos_token_id: Option<u32>,
    }
    let params: Params = match serde_json::from_str(params_str) {
        Ok(p) => p,
        Err(_) => return 1,
    };

    let config = InferenceConfig {
        temperature: params.temperature.unwrap_or(0.7),
        max_tokens: params.max_tokens.unwrap_or(1024),
        repeat_penalty: params.repeat_penalty.unwrap_or(1.1),
        repeat_last_n: params.repeat_last_n.unwrap_or(64),
        top_p: params.top_p.unwrap_or(0.9),
        seed: params.seed,
        eos_token_id: params.eos_token_id,
    };

    let engine = &mut *engine;
    let result = load_model_impl(&mut engine.inner, &dir_str, config);
    if result.is_ok() {
        0
    } else {
        1
    }
}

/// 加载模型实现（host target）：读取 config.json / tokenizer.json / mmap safetensors。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
fn load_model_impl(
    engine: &mut InferenceEngine,
    model_dir: &str,
    mut config: InferenceConfig,
) -> Result<(), InferenceError> {
    use std::path::Path;

    let dir = Path::new(model_dir);
    if !dir.exists() {
        return Err(InferenceError::NotFound(model_dir.into()));
    }

    // 加载 tokenizer
    let tokenizer = tokenizers::Tokenizer::from_file(dir.join("tokenizer.json"))
        .map_err(|e| InferenceError::Tokenizer(e.to_string()))?;

    // 读取 config.json
    let config_str = std::fs::read_to_string(dir.join("config.json"))
        .map_err(|e| InferenceError::Load(format!("读取 config.json 失败: {}", e)))?;
    let model_config: Qwen2Config = serde_json::from_str(&config_str)
        .map_err(|e| InferenceError::Load(format!("解析 config.json 失败: {}", e)))?;

    // EOS token id：从 config.json 原始 JSON 提取
    if config.eos_token_id.is_none() {
        let v: serde_json::Value =
            serde_json::from_str(&config_str).map_err(|e| InferenceError::Load(e.to_string()))?;
        if let Some(eos) = v.get("eos_token_id").and_then(|x| x.as_u64()) {
            config.eos_token_id = Some(eos as u32);
        }
    }

    // 设备：CPU（Metal/CUDA 需对应 feature）
    let device = Device::cuda_if_available(0).unwrap_or(Device::Cpu);

    // mmap safetensors（unsafe，集中在 FFI 层）
    let vb = unsafe {
        candle_nn::VarBuilder::from_mmaped_safetensors(
            &[dir.join("model.safetensors")],
            candle_core::DType::F32,
            &device,
        )
    }
    .map_err(|e| InferenceError::Load(e.to_string()))?;

    engine.load_from_components(vb, tokenizer, &model_config, device, config)
}

/// 流式生成文本，返回 JSON 数组（每个元素含 text 与 isEnd）。
/// 格式：`[{"text":"hello","isEnd":false},...]`
/// 调用方需用 `aether_free_string` 释放返回值。失败返回空指针。
/// # Safety
/// `engine` 来自 `aether_inference_new` 且已加载模型；`prompt` 合法 NUL 结尾 UTF-8。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_inference_generate(
    engine: *mut AetherInferenceEngine,
    prompt: *const c_char,
) -> *mut c_char {
    if engine.is_null() || prompt.is_null() {
        return std::ptr::null_mut();
    }
    let prompt = match CStr::from_ptr(prompt).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let engine = &*engine;
    match engine.inner.generate(prompt) {
        Ok(tokens) => {
            #[derive(serde::Serialize)]
            struct TokenView<'a> {
                text: &'a str,
                #[serde(rename = "isEnd")]
                is_end: bool,
            }
            let views: Vec<TokenView> = tokens
                .iter()
                .map(|t| TokenView {
                    text: &t.text,
                    is_end: t.is_end,
                })
                .collect();
            serde_json::to_string(&views)
                .map(|j| to_cstring(&j))
                .unwrap_or(std::ptr::null_mut())
        }
        Err(e) => {
            let json = format!(r#"{{"error":"{}"}}"#, e);
            to_cstring(&json)
        }
    }
}

/// 一次性生成完整文本，返回拼接后的字符串。
/// 调用方需用 `aether_free_string` 释放返回值。失败返回空指针。
/// # Safety
/// `engine` 来自 `aether_inference_new` 且已加载模型；`prompt` 合法 NUL 结尾 UTF-8。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_inference_generate_text(
    engine: *mut AetherInferenceEngine,
    prompt: *const c_char,
) -> *mut c_char {
    if engine.is_null() || prompt.is_null() {
        return std::ptr::null_mut();
    }
    let prompt = match CStr::from_ptr(prompt).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let engine = &*engine;
    match engine.inner.generate_text(prompt) {
        Ok(text) => to_cstring(&text),
        Err(e) => {
            let json = format!(r#"{{"error":"{}"}}"#, e);
            to_cstring(&json)
        }
    }
}

/// 模型是否已加载。
/// # Safety
/// `engine` 来自 `aether_inference_new`。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_inference_is_loaded(engine: *const AetherInferenceEngine) -> bool {
    if engine.is_null() {
        return false;
    }
    let engine = &*engine;
    engine.inner.is_loaded()
}

/// 卸载模型，释放内存。
/// # Safety
/// `engine` 来自 `aether_inference_new`。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_inference_unload(engine: *mut AetherInferenceEngine) {
    if engine.is_null() {
        return;
    }
    let engine = &mut *engine;
    engine.inner.unload();
}

/// 释放推理引擎。空指针安全。
/// # Safety
/// `engine` 来自 `aether_inference_new`，且只能释放一次。
#[cfg(not(any(target_arch = "wasm32", target_os = "android")))]
#[no_mangle]
pub unsafe extern "C" fn aether_inference_free(engine: *mut AetherInferenceEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
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
