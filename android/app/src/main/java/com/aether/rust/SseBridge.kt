package com.aether.rust

/**
 * Rust SSE 桥接：通过 JNI 调用 `aether-core-ffi` 的 `parse_with_tool_accumulation`。
 *
 * 对应 Rust 导出函数：`Java_com_aether_rust_SseBridge_parseWithTools`
 * / `Java_com_aether_rust_SseBridge_reset`。
 */
object SseBridge {
    init {
        System.loadLibrary("aether_core_ffi")
    }

    /**
     * 解析 SSE 行，返回 JSON 字符串 {"content":"...","toolCalls":[...]}。
     * 输入应为完整 SSE 行（含 `data: ` 前缀），Rust 内部 strip prefix。
     * 非 data 行 / 解析失败返回空串。
     */
    external fun parseWithTools(line: String): String

    /**
     * 重置累积状态（清空 thread-local tool_call 累积器）。
     */
    external fun reset()
}
