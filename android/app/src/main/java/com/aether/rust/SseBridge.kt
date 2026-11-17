package com.aether.rust

/**
 * Rust SSE 桥接：通过 JNI 调用 `aether-core-ffi` 的无状态单行解析。
 *
 * 对应 Rust 导出函数：`Java_com_aether_rust_SseBridge_parseChunk`。
 */
object SseBridge {
    init {
        System.loadLibrary("aether_core_ffi")
    }

    /**
     * 解析 SSE 行，返回 JSON 字符串 {"content":"..."}（无内容时为 {"content":null}）。
     * 输入应为完整 SSE 行（含 `data: ` 前缀），Rust 内部 strip prefix。
     * 非 data 行 / 解析失败返回空串。
     *
     * 无状态设计：早期跨 chunk 累积 tool_calls 的 thread_local 实现会在协程换线程时
     * 串流且永不释放，Android 侧只消费 content，故不再保留累积器。
     */
    external fun parseChunk(line: String): String
}
