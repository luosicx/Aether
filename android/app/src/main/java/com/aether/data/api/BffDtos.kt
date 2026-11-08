package com.aether.data.api

import com.aether.data.model.ChatMessage
import com.aether.data.model.Conversation
import com.aether.data.model.DocumentChunk
import com.aether.data.model.HealthSummary
import com.aether.data.model.Memory
import com.aether.data.model.ToolCall
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/**
 * BFF 响应 DTO：服务端返回 snake_case 字段，且在单资源 / 列表接口上使用 envelope。
 * 这些类型只用于网络层，通过 toModel() 映射为 UI 使用的领域模型。
 */
private val bffJson = Json { ignoreUnknownKeys = true }

@Serializable
internal data class ConversationsEnvelope(
    val conversations: List<ConversationDto> = emptyList()
)

@Serializable
internal data class ConversationEnvelope(
    val conversation: ConversationDto
)

@Serializable
internal data class ConversationDto(
    val id: String,
    val title: String = "",
    @SerialName("system_prompt") val systemPrompt: String? = null,
    @SerialName("parent_id") val parentId: String? = null,
    @SerialName("created_at") val createdAt: Long = 0,
    @SerialName("updated_at") val updatedAt: Long = 0,
    @SerialName("last_message_preview") val lastMessagePreview: String? = null,
    @SerialName("is_pinned") val isPinned: Int = 0,
    @SerialName("unread_count") val unreadCount: Int = 0,
    @SerialName("order_field") val orderField: Long = 0
) {
    fun toModel(): Conversation = Conversation(
        id = id,
        title = title,
        systemPrompt = systemPrompt ?: "你是一个有帮助的AI助手。",
        parentId = parentId,
        createdAt = createdAt,
        updatedAt = updatedAt,
        lastMessagePreview = lastMessagePreview ?: "",
        isPinned = isPinned != 0,
        unreadCount = unreadCount,
        // 服务端 order_field 为毫秒时间戳，超出 Int 范围；转秒保留排序且避免溢出
        order = (orderField / 1000L).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
    )
}

@Serializable
internal data class MessagesEnvelope(
    val messages: List<MessageDto> = emptyList()
)

@Serializable
internal data class MessageDto(
    val id: String,
    @SerialName("conversation_id") val conversationId: String,
    val role: String,
    val content: String = "",
    @SerialName("tool_calls") val toolCalls: JsonElement? = null,
    @SerialName("tool_call_id") val toolCallId: String? = null,
    @SerialName("tool_name") val toolName: String? = null,
    val feedback: Int? = null,
    @SerialName("created_at") val createdAt: Long = 0
) {
    fun toModel(): ChatMessage = ChatMessage(
        id = id,
        conversationId = conversationId,
        role = role,
        content = content,
        toolCalls = toolCalls.toToolCalls(),
        toolCallId = toolCallId,
        toolName = toolName,
        feedback = feedback,
        createdAt = createdAt
    )
}

private fun JsonElement?.toToolCalls(): List<ToolCall>? {
    val array = when (val element = this) {
        null -> return null
        is JsonArray -> element
        is JsonPrimitive -> runCatching {
            bffJson.parseToJsonElement(element.content) as? JsonArray
        }.getOrNull()
        else -> null
    } ?: return null
    return runCatching {
        bffJson.decodeFromJsonElement(ListSerializer(ToolCall.serializer()), array)
    }.getOrNull()
}

@Serializable
internal data class MemoriesEnvelope(
    val memories: List<MemoryDto> = emptyList()
)

@Serializable
internal data class MemoryEnvelope(
    val memory: MemoryDto
)

@Serializable
internal data class MemoryDto(
    val id: String,
    val content: String,
    val category: String? = null,
    val importance: Double = 0.5,
    @SerialName("created_at") val createdAt: Long = 0
) {
    fun toModel(): Memory = Memory(
        id = id,
        content = content,
        category = category ?: "context",
        importance = importance,
        createdAt = createdAt
    )
}

@Serializable
internal data class ChunksEnvelope(
    val chunks: List<DocumentChunkDto> = emptyList()
)

@Serializable
internal data class DocumentChunkDto(
    val id: String,
    @SerialName("document_id") val documentId: String? = null,
    val content: String,
    @SerialName("document_title") val documentTitle: String? = null,
    @SerialName("chunk_index") val chunkIndex: Int = 0,
    val weight: Float = 1.0f,
    @SerialName("created_at") val createdAt: Long = 0
) {
    fun toModel(): DocumentChunk = DocumentChunk(
        id = id,
        documentId = documentId,
        content = content,
        source = documentTitle ?: "",
        chunkIndex = chunkIndex,
        weight = weight,
        createdAt = createdAt
    )
}

@Serializable
internal data class HealthSummaryEnvelope(
    val summary: HealthSummaryDto
)

@Serializable
internal data class HealthSummaryDto(
    val date: String,
    val steps: Int? = null,
    @SerialName("sleep_hours") val sleepHours: Double? = null,
    @SerialName("resting_heart_rate") val restingHeartRate: Int? = null
) {
    fun toModel(): HealthSummary = HealthSummary(
        date = date,
        steps = steps,
        sleepHours = sleepHours,
        restingHeartRate = restingHeartRate
    )
}
