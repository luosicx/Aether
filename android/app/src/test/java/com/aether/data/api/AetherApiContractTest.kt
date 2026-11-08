package com.aether.data.api

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BFF 契约回归测试：用服务端真实响应格式（envelope + snake_case）驱动 AetherApi，
 * 防止客户端模型与 Worker 输出再次漂移。
 */
class AetherApiContractTest {

    private val requestLog = mutableListOf<Pair<HttpMethod, String>>()
    private var lastRequestBody: String = ""

    private fun api(
        payload: String,
        status: HttpStatusCode = HttpStatusCode.OK
    ): AetherApi {
        val engine = MockEngine { request ->
            requestLog += request.method to request.url.encodedPath
            lastRequestBody = (request.body as? OutgoingContent.ByteArrayContent)
                ?.bytes()
                ?.decodeToString()
                ?: ""
            respond(
                content = payload,
                status = status,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val client = HttpClient(engine) {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true; encodeDefaults = true })
            }
        }
        return AetherApi(client, BffConfig(baseUrl = "https://bff.test", userToken = "test-token"))
    }

    private fun conversationPayload(id: String = "c1", title: String = "会话一") = """
        {
          "id": "$id",
          "user_id": "u1",
          "title": "$title",
          "parent_id": null,
          "created_at": 1700000000000,
          "updated_at": 1700000005000,
          "last_message_preview": "你好",
          "is_pinned": 1,
          "system_prompt": "你是助手",
          "unread_count": 2,
          "order_field": 1700000000000
        }
    """.trimIndent()

    @Test
    fun listConversationsDecodesEnvelopeAndSnakeCase() = runTest {
        val api = api(payload = """{"conversations": [${conversationPayload()}]}""")

        val result = api.listConversations()

        assertEquals(1, result.size)
        val conv = result.single()
        assertEquals("c1", conv.id)
        assertEquals("会话一", conv.title)
        assertEquals("你是助手", conv.systemPrompt)
        assertEquals("你好", conv.lastMessagePreview)
        assertTrue(conv.isPinned)
        assertEquals(2, conv.unreadCount)
        assertEquals(1700000000000L, conv.createdAt)
        assertEquals(1700000000, conv.order)
        assertEquals(HttpMethod.Get to "/conversations", requestLog.single())
    }

    @Test
    fun createConversationDecodesEnvelope() = runTest {
        val api = api(
            status = HttpStatusCode.Created,
            payload = """{"conversation": ${conversationPayload(id = "new-1", title = "新会话")}}"""
        )

        val conv = api.createConversation("新会话")

        assertEquals("new-1", conv.id)
        assertEquals("新会话", conv.title)
        assertEquals(HttpMethod.Post to "/conversations", requestLog.single())
        assertTrue(lastRequestBody.contains("\"title\":\"新会话\""))
    }

    @Test
    fun updateConversationSendsCamelCaseAndDecodesEnvelope() = runTest {
        val api = api(payload = """{"conversation": ${conversationPayload(title = "改名")}}""")

        val conv = api.updateConversation("c1", title = "改名", isPinned = true)

        assertEquals("改名", conv.title)
        assertEquals(HttpMethod.Patch to "/conversations/c1", requestLog.single())
        val body = Json.parseToJsonElement(lastRequestBody).jsonObject
        assertEquals("改名", body["title"]?.jsonPrimitive?.content)
        assertEquals(true, body["isPinned"]?.jsonPrimitive?.content?.toBoolean())
    }

    @Test
    fun listMessagesDecodesEnvelopeAndToolCalls() = runTest {
        val api = api(
            payload = """
                {
                  "messages": [
                    {
                      "id": "m1",
                      "conversation_id": "c1",
                      "role": "assistant",
                      "content": "好的",
                      "tool_calls": "[{\"id\":\"tc1\",\"name\":\"search\",\"arguments\":\"{}\"}]",
                      "tool_call_id": null,
                      "tool_name": null,
                      "feedback": 1,
                      "created_at": 1700000001000
                    }
                  ]
                }
            """.trimIndent()
        )

        val messages = api.listMessages("c1")

        assertEquals(1, messages.size)
        val msg = messages.single()
        assertEquals("c1", msg.conversationId)
        assertEquals(1, msg.feedback)
        assertEquals(1, msg.toolCalls?.size)
        assertEquals("search", msg.toolCalls?.single()?.name)
        assertEquals(HttpMethod.Get to "/conversations/c1/messages", requestLog.single())
    }

    @Test
    fun listMessagesAcceptsToolCallsArray() = runTest {
        val api = api(
            payload = """
                {
                  "messages": [
                    {
                      "id": "m2",
                      "conversation_id": "c1",
                      "role": "assistant",
                      "content": "",
                      "tool_calls": [{"id": "tc2", "name": "calc", "arguments": "{}"}],
                      "created_at": 1700000002000
                    }
                  ]
                }
            """.trimIndent()
        )

        val msg = api.listMessages("c1").single()

        assertEquals("calc", msg.toolCalls?.single()?.name)
    }

    @Test
    fun memoryEndpointsDecodeEnvelopes() = runTest {
        val memory = """
            {
              "id": "mem-1",
              "user_id": "u1",
              "content": "用户喜欢咖啡",
              "category": null,
              "importance": 0.8,
              "source_conversation_id": null,
              "created_at": 1700000003000
            }
        """.trimIndent()

        val listApi = api(payload = """{"memories": [$memory]}""")
        val listed = listApi.listMemory().single()
        assertEquals("mem-1", listed.id)
        assertEquals("context", listed.category)
        assertEquals(0.8, listed.importance, 0.0001)

        val createApi = api(
            status = HttpStatusCode.Created,
            payload = """{"memory": $memory}"""
        )
        val created = createApi.createMemory("用户喜欢咖啡")
        assertEquals("mem-1", created.id)

        val searchApi = api(payload = """{"memories": [$memory], "query": "咖啡"}""")
        val searched = searchApi.searchMemory("咖啡")
        assertEquals(1, searched.size)
    }

    @Test
    fun searchDocumentsDecodesChunkFields() = runTest {
        val api = api(
            payload = """
                {
                  "chunks": [
                    {
                      "id": "ch1",
                      "document_id": "d1",
                      "content": "咖啡因可短暂提神",
                      "metadata": "{\"index\":0}",
                      "chunk_index": 3,
                      "weight": 0.75,
                      "document_title": "咖啡百科"
                    }
                  ],
                  "query": "咖啡"
                }
            """.trimIndent()
        )

        val chunk = api.searchDocuments("咖啡").single()

        assertEquals("ch1", chunk.id)
        assertEquals("d1", chunk.documentId)
        assertEquals("咖啡百科", chunk.source)
        assertEquals(3, chunk.chunkIndex)
        assertEquals(0.75f, chunk.weight, 0.0001f)
        assertEquals(0L, chunk.createdAt)
    }

    @Test
    fun getHealthSummaryDecodesEnvelopeAndSnakeCase() = runTest {
        val api = api(
            payload = """
                {
                  "summary": {
                    "user_id": "u1",
                    "date": "2026-11-08",
                    "steps": 8000,
                    "sleep_hours": 7.5,
                    "resting_heart_rate": 58
                  }
                }
            """.trimIndent()
        )

        val summary = api.getHealthSummary("2026-11-08")

        assertEquals("2026-11-08", summary?.date)
        assertEquals(8000, summary?.steps)
        assertEquals(7.5, summary?.sleepHours ?: 0.0, 0.0001)
        assertEquals(58, summary?.restingHeartRate)
    }

    @Test
    fun getHealthSummaryReturnsNullOnNotFound() = runTest {
        val api = api(
            payload = """{"error": "该日期无健康摘要"}""",
            status = HttpStatusCode.NotFound
        )

        assertNull(api.getHealthSummary("2026-11-09"))
    }

    @Test
    fun submitFeedbackSendsServerContractField() = runTest {
        val positive = api(payload = """{"id":"m1","feedback":1}""")
        positive.submitFeedback("m1", isPositive = true)
        assertEquals(
            1,
            Json.parseToJsonElement(lastRequestBody).jsonObject["feedback"]?.jsonPrimitive?.content?.toInt()
        )

        val negative = api(payload = """{"id":"m1","feedback":-1}""")
        negative.submitFeedback("m1", isPositive = false)
        assertEquals(
            -1,
            Json.parseToJsonElement(lastRequestBody).jsonObject["feedback"]?.jsonPrimitive?.content?.toInt()
        )

        val cleared = api(payload = """{"id":"m1","feedback":null}""")
        cleared.submitFeedback("m1", isPositive = null)
        assertEquals(
            0,
            Json.parseToJsonElement(lastRequestBody).jsonObject["feedback"]?.jsonPrimitive?.content?.toInt()
        )
    }
}
