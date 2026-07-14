package com.aether.data.api

import com.aether.data.model.ChatRequest
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
     */
    fun streamChat(request: ChatRequest): Flow<String> = channelFlow {
        val response = client.post("${config.baseUrl}/chat/stream") {
            header("X-BFF-Token", config.userToken)
            accept(ContentType.Text.EventStream)
            contentType(ContentType.Application.Json)
            setBody(request)
        }

        val channel = response.bodyAsChannel()
        val json = Json { ignoreUnknownKeys = true }

        while (!channel.isClosedForRead) {
            val line = channel.readUTF8Line() ?: break
            if (line.startsWith("data: ")) {
                val data = line.removePrefix("data: ").trim()
                if (data == "[DONE]") {
                    close()
                    return@channelFlow
                }
                if (data.isNotEmpty()) {
                    try {
                        val obj = json.parseToJsonElement(data).jsonObject
                        val type = obj["type"]?.jsonPrimitive?.content
                        if (type == "delta") {
                            val content = obj["content"]?.jsonPrimitive?.content ?: ""
                            send(content)
                        } else if (type == "done") {
                            close()
                            return@channelFlow
                        }
                    } catch (e: Exception) {
                        // 忽略解析错误，继续读取
                    }
                }
            }
        }
        close()
    }
}
