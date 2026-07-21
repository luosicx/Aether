package com.aether.data.api

import com.aether.app.BuildConfig
import io.ktor.client.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json

object HttpClientFactory {
    fun create(): HttpClient = HttpClient {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
            })
        }
        install(Logging) {
            // release 构建关闭日志，避免 BFF Token / Authorization header 泄露到 logcat；
            // debug 构建保留 HEADERS 级别便于排查问题
            level = if (BuildConfig.DEBUG) LogLevel.HEADERS else LogLevel.NONE
            // 即便在 debug 下，也过滤掉敏感 header，防止意外泄露
            sanitizeHeader { header -> header in listOf("Authorization", "X-BFF-Token") }
        }
    }
}
