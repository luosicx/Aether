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
import java.io.IOException

/**
 * 流式对话来源。抽出接口是为了让 ViewModel 能在纯 JVM 测试中替换实现：
 * 真实 SSE 解析依赖 Rust JNI，测试环境没有 .so。
 */
fun interface ChatStreamSource {
    fun streamChat(request: ChatRequest): Flow<String>
}

class ChatStreamClient(private val client: HttpClient, private val config: BffConfig) : ChatStreamSource {

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * 流式聊天：通过 SSE 接收 LLM 流式响应。
     * 解析 SSE 事件格式：data: {"type":"delta","content":"..."}\n\n
     * 终止信号：data: [DONE]\n\n
     *
     * SSE 解析统一走 Rust JNI（无状态单行解析，同时支持 OpenAI choices 与 BFF type/content 两种 envelope）。
     */
    override fun streamChat(request: ChatRequest): Flow<String> = channelFlow {
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
                    // BFF 出错时 HTTP 已是 200，错误只以流内事件下发；
                    // 不识别会被当作 done，界面表现为没有任何提示的空回复。
                    bffErrorMessage(data)?.let { throw IOException(it) }
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
     * 识别 BFF 流内错误事件 `{"type":"error","message":"..."}`（服务端已脱敏）。
     * 消息缺失时返回兜底文案；非 error 事件 / 非 JSON 返回 null。纯 Kotlin 解析，不依赖 JNI。
     */
    internal fun bffErrorMessage(data: String): String? {
        val obj = runCatching { json.parseToJsonElement(data).jsonObject }.getOrNull() ?: return null
        if ((obj["type"] as? JsonPrimitive)?.contentOrNull != "error") return null
        val message = (obj["message"] as? JsonPrimitive)?.contentOrNull
        return message?.takeIf { it.isNotEmpty() } ?: "服务暂时不可用，请稍后再试"
    }

    /**
     * 解析单行 SSE（Rust JNI，统一支持 OpenAI 与 BFF 两种 envelope）。
     * 入参为完整 SSE 行（含 `data: ` 前缀）。
     * 返回 delta content；非 delta 行或无 content 返回 null。
     * JNI 不可用（打包损坏）时返回 null，不崩溃。
     */
    fun parseLine(line: String): String? {
        val rust = try {
            SseBridge.parseChunk(line)
        } catch (e: Throwable) {
            return null
        }
        if (rust.isEmpty()) return null
        return try {
            // Rust 返回 {"content":"..."} 或 {"content":null}
            val parsed = json.parseToJsonElement(rust).jsonObject
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
