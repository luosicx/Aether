package com.aether.data.api

import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.HttpTimeoutConfig
import io.ktor.client.plugins.plugin
import org.junit.Assert.assertEquals
import org.junit.Test

class HttpClientFactoryTest {
    @Test
    fun `http timeout is configured for sse streams`() {
        val client = HttpClientFactory.create()
        try {
            val config = timeoutConfig(client)
            assertEquals(15_000L, config.connectTimeoutMillis)
            assertEquals(30_000L, config.socketTimeoutMillis)
        } finally {
            client.close()
        }
    }

    // Ktor 3 的 client.plugin(HttpTimeout) 返回 ClientPluginInstance，配置仅存在于其私有字段
    private fun timeoutConfig(client: HttpClient): HttpTimeoutConfig {
        val instance = client.plugin(HttpTimeout)
        val field = instance.javaClass.getDeclaredField("config").apply { isAccessible = true }
        return field.get(instance) as HttpTimeoutConfig
    }
}
