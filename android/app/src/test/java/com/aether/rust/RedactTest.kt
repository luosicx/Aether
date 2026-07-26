package com.aether.rust

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Redact 单元测试。
 *
 * 纯 JVM 测试环境中 JNI（libaether_core_ffi.so）不可用，
 * [Redact.redactSafe] 应回退返回原文，不抛异常。
 */
class RedactTest {

    @Test
    fun redactSafeReturnsOriginalWhenJniUnavailable() {
        val input = "用户 user@example.com 访问 https://example.com"
        val result = Redact.redactSafe(input)
        // JNI 不可用时直接返回原文
        assertEquals(input, result)
    }

    @Test
    fun redactSafeHandlesEmptyString() {
        val result = Redact.redactSafe("")
        assertEquals("", result)
    }

    @Test
    fun redactSafeHandlesPlainMessage() {
        val input = "Network timeout: 连接超时"
        val result = Redact.redactSafe(input)
        assertEquals(input, result)
    }

    @Test
    fun redactSafeHandlesMultilineInput() {
        val input = """
            第一行 user@test.com
            第二行 sk-abc123xyz
            第三行 /Users/alice/.ssh/id_rsa
        """.trimIndent()
        // JNI 不可用时不论输入多复杂都应原样返回
        val result = Redact.redactSafe(input)
        assertEquals(input, result)
    }

    @Test
    fun redactSafeIsIdempotentWhenJniUnavailable() {
        val input = "包含 Bearer token 与 UUID 550e8400-e29b-41d4-a716-446655440000"
        val first = Redact.redactSafe(input)
        val second = Redact.redactSafe(first)
        assertEquals(first, second)
    }
}
