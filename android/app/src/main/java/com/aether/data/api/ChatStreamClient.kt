package com.aether.data.api

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
     * SSE 解析统一走 Rust JNI（同时支持 OpenAI choices 与 BFF type/content 两种 envelope）。
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
     * 解析单行 SSE（Rust JNI，统一支持 OpenAI 与 BFF 两种 envelope）。
     * 入参为完整 SSE 行（含 `data: ` 前缀）。
     * 返回 delta content；非 delta 行或无 content 返回 null。
     * JNI 不可用（打包损坏）时返回 null，不崩溃。
     */
    fun parseLine(line: String): String? {
        val rust = try {
            SseBridge.parseWithTools(line)
        } catch (e: Throwable) {
            return null
        }
        if (rust.isEmpty()) return null
        return try {
            // Rust 返回 {"content":"...","toolCalls":[...],"usage":{...}}
            val parsed = Json { ignoreUnknownKeys = true }
                .parseToJsonElement(rust).jsonObject
            val contentElem = parsed["content"]
            if (contentElem != null && contentElem is JsonPrimitive && contentElem !is JsonNull) {
                contentElem.jsonPrimitive.content
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }
}
