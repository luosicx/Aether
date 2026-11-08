package com.aether.data.api

import com.aether.data.model.*
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class AetherApi(private val client: HttpClient, private val config: BffConfig) {

    private fun HttpRequestBuilder.withAuth() {
        header("X-BFF-Token", config.userToken)
        contentType(ContentType.Application.Json)
    }

    // 会话
    suspend fun listConversations(): List<Conversation> =
        client.get("${config.baseUrl}/conversations") { withAuth() }
            .body<ConversationsEnvelope>()
            .conversations
            .map { it.toModel() }

    suspend fun createConversation(title: String): Conversation =
        client.post("${config.baseUrl}/conversations") {
            withAuth()
            setBody(buildJsonObject { put("title", title) })
        }.body<ConversationEnvelope>().conversation.toModel()

    suspend fun getConversation(id: String): Conversation =
        client.get("${config.baseUrl}/conversations/$id") { withAuth() }
            .body<ConversationEnvelope>()
            .conversation
            .toModel()

    suspend fun updateConversation(id: String, title: String? = null, isPinned: Boolean? = null): Conversation =
        client.patch("${config.baseUrl}/conversations/$id") {
            withAuth()
            setBody(buildJsonObject {
                title?.let { put("title", it) }
                isPinned?.let { put("isPinned", it) }
            })
        }.body<ConversationEnvelope>().conversation.toModel()

    suspend fun deleteConversation(id: String) {
        client.delete("${config.baseUrl}/conversations/$id") { withAuth() }
    }

    // 消息
    suspend fun listMessages(conversationId: String): List<ChatMessage> =
        client.get("${config.baseUrl}/conversations/$conversationId/messages") { withAuth() }
            .body<MessagesEnvelope>()
            .messages
            .map { it.toModel() }

    suspend fun deleteMessage(messageId: String) {
        client.delete("${config.baseUrl}/messages/$messageId") { withAuth() }
    }

    suspend fun submitFeedback(messageId: String, isPositive: Boolean?, citations: List<String>? = null) {
        // 服务端契约：feedback 为 1 / -1 / 0（0 表示取消反馈）
        val feedback = when (isPositive) {
            true -> 1
            false -> -1
            null -> 0
        }
        client.post("${config.baseUrl}/messages/$messageId/feedback") {
            withAuth()
            setBody(buildJsonObject { put("feedback", feedback) })
        }
    }

    // 记忆
    suspend fun listMemory(): List<Memory> =
        client.get("${config.baseUrl}/memory") { withAuth() }
            .body<MemoriesEnvelope>()
            .memories
            .map { it.toModel() }

    suspend fun createMemory(content: String, category: String = "context", importance: Double = 0.5): Memory =
        client.post("${config.baseUrl}/memory") {
            withAuth()
            setBody(buildJsonObject {
                put("content", content)
                put("category", category)
                put("importance", importance)
            })
        }.body<MemoryEnvelope>().memory.toModel()

    suspend fun searchMemory(query: String, limit: Int = 5): List<Memory> =
        client.post("${config.baseUrl}/memory/search") {
            withAuth()
            setBody(MemorySearchRequest(query, limit))
        }.body<MemoriesEnvelope>().memories.map { it.toModel() }

    suspend fun deleteMemory(id: String) {
        client.delete("${config.baseUrl}/memory/$id") { withAuth() }
    }

    // RAG
    suspend fun searchDocuments(query: String, limit: Int = 3): List<DocumentChunk> =
        client.post("${config.baseUrl}/rag/search") {
            withAuth()
            setBody(RagSearchRequest(query, limit))
        }.body<ChunksEnvelope>().chunks.map { it.toModel() }

    // 健康
    suspend fun uploadHealthSummary(summary: HealthSummary) {
        client.post("${config.baseUrl}/health/summary") {
            withAuth()
            setBody(summary)
        }
    }

    suspend fun getHealthSummary(date: String): HealthSummary? {
        val response = client.get("${config.baseUrl}/health/summary/$date") { withAuth() }
        return if (response.status == HttpStatusCode.OK) {
            response.body<HealthSummaryEnvelope>().summary.toModel()
        } else {
            null
        }
    }
}
