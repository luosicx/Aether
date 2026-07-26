package com.aether.rust

/**
 * Rust 脱敏 JNI 桥接。
 *
 * 调用 Rust aether_core_ffi 的 aether_redact 函数，
 * 对输入文本中的 UUID / 邮箱 / URL / Token 进行脱敏。
 *
 * JNI 不可用时（纯 JVM 测试环境）返回原文，不抛异常。
 */
object Redact {
    // 不用 init { System.loadLibrary }：init 抛 UnsatisfiedLinkError 会导致对象
    // 永久初始化失败（后续访问抛 NoClassDefFoundError），safe 包装无法生效。
    private val nativeLoaded: Boolean = try {
        System.loadLibrary("aether_core_ffi")
        true
    } catch (e: UnsatisfiedLinkError) {
        false
    }

    /**
     * 对输入文本进行脱敏。
     *
     * 调用 Rust 端 [aether_core_ffi::aether_redact] 等价实现（UUID/邮箱/URL/Token/凭证/路径）。
     *
     * @param input 原始文本
     * @return 脱敏后文本
     */
    external fun redact(input: String): String

    /**
     * 安全版本：JNI 不可用或调用异常时返回原文。
     *
     * 供无 .so 产物（如纯 JVM 测试）的回退场景使用。
     */
    fun redactSafe(input: String): String {
        if (!nativeLoaded) return input
        return try {
            redact(input)
        } catch (e: UnsatisfiedLinkError) {
            input
        }
    }
}
