package com.aether.rust

import com.aether.data.api.BffConfig
import com.aether.data.api.ChatStreamClient
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respondOk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * SseBridge 单元测试。
 *
 * 纯 JVM 测试环境中 JNI（libaether_core_ffi.so）不可用，SseBridge 对象初始化会抛
 * UnsatisfiedLinkError → ExceptionInInitializerError。ChatStreamClient.parseLine
 * 捕获后回退到 parseLineKotlin，此测试验证回退路径正确性。
 */
class SseBridgeTest {

    private val client = HttpClient(MockEngine { respondOk("") })
    private val config = BffConfig(baseUrl = "http://test", userToken = "")
    private val streamClient = ChatStreamClient(client, config)

    @Test
    fun parseLineFallsBackToKotlinForDeltaContent() {
        // BFF 自定义格式（Rust 无法解析 → 回退 Kotlin）
        val line = """data: {"type":"delta","content":"hello"}"""
        val content = streamClient.parseLine(line)
        assertEquals("hello", content)
    }

    @Test
    fun parseLineReturnsNullForDoneType() {
        val line = """data: {"type":"done"}"""
        val content = streamClient.parseLine(line)
        assertNull(content)
    }

    @Test
    fun parseLineReturnsNullForInvalidJson() {
        val line = "data: not-json"
        val content = streamClient.parseLine(line)
        assertNull(content)
    }

    @Test
    fun parseLineHandlesNullContent() {
        val line = """data: {"type":"delta","content":null}"""
        val content = streamClient.parseLine(line)
        assertNull(content)
    }

    @Test
    fun parseLineReturnsNullForNonDataLine() {
        // 非 data: 前缀行 — Rust 和 Kotlin 都不匹配
        val line = "event: ping"
        val content = streamClient.parseLine(line)
        assertNull(content)
    }
}
