package com.aether.rust

import com.aether.data.api.BffConfig
import com.aether.data.api.ChatStreamClient
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respondOk
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * SseBridge 降级行为单元测试。
 *
 * 纯 JVM 测试环境中 JNI（libaether_core_ffi.so）不可用，SseBridge 对象初始化会抛
 * UnsatisfiedLinkError → ExceptionInInitializerError。SSE 解析逻辑统一在 Rust 侧
 * （aether-core sse.rs 单测覆盖 OpenAI 与 BFF 两种 envelope）；此处验证 JNI 不可用时
 * ChatStreamClient.parseLine 不崩溃、返回 null。
 */
class SseBridgeTest {

    private val client = HttpClient(MockEngine { respondOk("") })
    private val config = BffConfig(baseUrl = "http://test", userToken = "")
    private val streamClient = ChatStreamClient(client, config)

    @Test
    fun parseLineReturnsNullForBffDeltaWhenJniUnavailable() {
        val line = """data: {"type":"delta","content":"hello"}"""
        assertNull(streamClient.parseLine(line))
    }

    @Test
    fun parseLineReturnsNullForOpenAiChunkWhenJniUnavailable() {
        val line = """data: {"choices":[{"delta":{"content":"hi"}}]}"""
        assertNull(streamClient.parseLine(line))
    }

    @Test
    fun parseLineReturnsNullForDone() {
        assertNull(streamClient.parseLine("data: [DONE]"))
    }

    @Test
    fun parseLineReturnsNullForNonDataLine() {
        assertNull(streamClient.parseLine("event: ping"))
    }
}