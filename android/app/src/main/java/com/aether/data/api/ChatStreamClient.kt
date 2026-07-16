package com.aether.data.api

import com.aether.app.BuildConfig
import com.aether.data.model.ChatRequest
import com.aether.rust.SseBridge
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.utils.io.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*

class ChatStreamClient(private val client: HttpClient, private val config: BffConfig) {

    /**
     * 流式聊天：通过 SSE 接收 LLM 流式响应。
     * 解析 SSE 事件格式：data: {"type":"delta","content":"..."}\n\n
     * 终止信号：data: [DONE]\n\n
     *
     * SSE 解析优先走 Rust JNI（OpenAI choices 格式），失败回退到纯 Kotlin（自定义 type/content 格式）。
     */
    fun streamChat(request: ChatRequest): Flow<String> = channelFlow {
        val response = client.post("${config.baseUrl}/chat/stream") {
            header("X-BFF-Token", config.userToken)
            accept(ContentType.Text.EventStream)
            contentType(ContentType.Application.Json)
            setBody(request)
        }

        val channel = response.bodyAsChannel()

        while (!channel.isClosedForRead) {
            val line = channel.readUTF8Line() ?: break
            if (line.startsWith("data: ")) {
                val data = line.removePrefix("data: ").trim()
                if (data == "[DONE]") {
                    close()
                    return@channelFlow
                }
                if (data.isNotEmpty()) {
                    val content = parseLine(line)
                    if (content != null && content.isNotEmpty()) {
                        send(content)
                    }
                }
            }
        }
        close()
    }

    /**
     * 解析单行 SSE：优先 Rust JNI，失败回退纯 Kotlin。
     * 入参为完整 SSE 行（含 `data: ` 前缀）。
     * 返回 delta content；非 delta 行或无 content 返回 null。
     */
    fun parseLine(line: String): String? {
        if (BuildConfig.USE_RUST_SSE) {
            try {
                val rust = SseBridge.parseWithTools(line)
                if (rust.isNotEmpty()) {
                    // Rust 返回 {"content":"...","toolCalls":[...]}
                    val parsed = Json { ignoreUnknownKeys = true }
                        .parseToJsonElement(rust).jsonObject
                    val contentElem = parsed["content"]
                    return if (contentElem != null && contentElem is kotlinx.serialization.json.JsonPrimitive) {
                        contentElem.jsonPrimitive.content
                    } else {
                        null
                    }
                }
                // 空串：Rust 未识别此行，回退到 Kotlin
            } catch (e: Throwable) {
                // JNI 不可用或解析异常，回退到 Kotlin
            }
        }
        return parseLineKotlin(line)
    }

    /**
     * 纯 Kotlin SSE 解析（fallback）。
     * 处理 BFF 自定义格式：data: {"type":"delta","content":"..."}
     */
    private fun parseLineKotlin(line: String): String? {
        return try {
            val data = line.removePrefix("data: ").trim()
            val json = Json { ignoreUnknownKeys = true }
            val obj = json.parseToJsonElement(data).jsonObject
            val type = obj["type"]?.jsonPrimitive?.content
            if (type == "delta") {
                val contentElem = obj["content"]
                if (contentElem != null && contentElem is kotlinx.serialization.json.JsonPrimitive) {
                    contentElem.jsonPrimitive.content
                } else {
                    null
                }
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }
}
