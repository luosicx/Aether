package com.aether.data.model

import kotlinx.serialization.Serializable

@Serializable
data class Conversation(
    val id: String,
    val title: String,
    val systemPrompt: String = "你是一个有帮助的AI助手。",
    val parentId: String? = null,
    val createdAt: Long,
    val updatedAt: Long,
    val lastMessagePreview: String = "",
    val isPinned: Boolean = false,
    val unreadCount: Int = 0,
    val order: Int = 0
)

@Serializable
data class ChatMessage(
    val id: String,
    val conversationId: String,
    val role: String,
    val content: String,
    val toolCalls: List<ToolCall>? = null,
    val toolCallId: String? = null,
    val toolName: String? = null,
    val feedback: Int? = null,
    val createdAt: Long
)

@Serializable
data class ToolCall(
    val id: String,
    val name: String,
    val arguments: String
)

@Serializable
data class ChatRequest(
    val message: String,
    val conversationId: String,
    val model: String = "deepseek-chat",
    val memoryEnabled: Boolean = true
)

@Serializable
data class Memory(
    val id: String,
    val content: String,
    val category: String = "context",
    val importance: Double = 0.5,
    val createdAt: Long
)

@Serializable
data class MemorySearchRequest(
    val query: String,
    val limit: Int = 5
)

@Serializable
data class DocumentChunk(
    val id: String,
    val documentId: String? = null,
    val content: String,
    val source: String = "",
    val chunkIndex: Int = 0,
    val weight: Float = 1.0f,
    val createdAt: Long
)

@Serializable
data class RagSearchRequest(
    val query: String,
    val limit: Int = 3
)

@Serializable
data class HealthSummary(
    val date: String,
    val steps: Int? = null,
    val sleepHours: Double? = null,
    val restingHeartRate: Int? = null
)
