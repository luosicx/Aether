package com.aether.data.api

import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.plugin
import org.junit.Assert.assertEquals
import org.junit.Test

class HttpClientFactoryTest {
    @Test
    fun `http timeout is configured for sse streams`() {
        val client = HttpClientFactory.create()
        try {
            val plugin = client.plugin(HttpTimeout)
            // Ktor 2.3.x 的 HttpTimeout 实例没有公开 getter，字段名随 Ktor 版本固定
            assertEquals(15_000L, timeoutField(plugin, "connectTimeoutMillis"))
            assertEquals(30_000L, timeoutField(plugin, "socketTimeoutMillis"))
        } finally {
            client.close()
        }
    }

    private fun timeoutField(plugin: HttpTimeout, name: String): Long {
        val field = HttpTimeout::class.java.getDeclaredField(name).apply { isAccessible = true }
        return (field.get(plugin) as Number).toLong()
    }
}
