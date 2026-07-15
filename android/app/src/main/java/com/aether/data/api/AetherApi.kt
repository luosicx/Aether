package com.aether.data.api

import com.aether.data.model.*
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*

class AetherApi(private val client: HttpClient, private val config: BffConfig) {

    private fun HttpRequestBuilder.withAuth() {
        header("X-BFF-Token", config.userToken)
        contentType(ContentType.Application.Json)
    }

    // 会话
    suspend fun listConversations(): List<Conversation> =
        client.get("${config.baseUrl}/conversations") { withAuth() }.body()

    suspend fun createConversation(title: String): Conversation {
        val response = client.post("${config.baseUrl}/conversations") {
            withAuth()
            setBody(mapOf("title" to title))
        }
        return response.body()
    }

    suspend fun getConversation(id: String): Conversation =
        client.get("${config.baseUrl}/conversations/$id") { withAuth() }.body()

    suspend fun updateConversation(id: String, title: String? = null, isPinned: Boolean? = null): Conversation {
        val body = mutableMapOf<String, Any>()
        title?.let { body["title"] = it }
        isPinned?.let { body["isPinned"] = it }
        val response = client.patch("${config.baseUrl}/conversations/$id") {
            withAuth()
            setBody(body)
        }
        return response.body()
    }

    suspend fun deleteConversation(id: String) {
        client.delete("${config.baseUrl}/conversations/$id") { withAuth() }
    }

    // 消息
    suspend fun listMessages(conversationId: String): List<ChatMessage> =
        client.get("${config.baseUrl}/conversations/$conversationId/messages") { withAuth() }.body()

    suspend fun deleteMessage(messageId: String) {
        client.delete("${config.baseUrl}/messages/$messageId") { withAuth() }
    }

    suspend fun submitFeedback(messageId: String, isPositive: Boolean?, citations: List<String>? = null) {
        client.post("${config.baseUrl}/messages/$messageId/feedback") {
            withAuth()
            setBody(mapOf("isPositive" to isPositive, "citations" to citations))
        }
    }

    // 记忆
    suspend fun listMemory(): List<Memory> =
        client.get("${config.baseUrl}/memory") { withAuth() }.body()

    suspend fun createMemory(content: String, category: String = "context", importance: Double = 0.5): Memory {
        val response = client.post("${config.baseUrl}/memory") {
            withAuth()
            setBody(mapOf("content" to content, "category" to category, "importance" to importance))
        }
        return response.body()
    }

    suspend fun searchMemory(query: String, limit: Int = 5): List<Memory> {
        val response = client.post("${config.baseUrl}/memory/search") {
            withAuth()
            setBody(MemorySearchRequest(query, limit))
        }
        return response.body()
    }

    suspend fun deleteMemory(id: String) {
        client.delete("${config.baseUrl}/memory/$id") { withAuth() }
    }

    // RAG
    suspend fun searchDocuments(query: String, limit: Int = 3): List<DocumentChunk> {
        val response = client.post("${config.baseUrl}/rag/search") {
            withAuth()
            setBody(RagSearchRequest(query, limit))
        }
        return response.body()
    }

    // 健康
    suspend fun uploadHealthSummary(summary: HealthSummary) {
        client.post("${config.baseUrl}/health/summary") {
            withAuth()
            setBody(summary)
        }
    }

    suspend fun getHealthSummary(date: String): HealthSummary? {
        val response = client.get("${config.baseUrl}/health/summary/$date") { withAuth() }
        return if (response.status == HttpStatusCode.OK) response.body() else null
    }
}
