package com.aether.data.repository

import com.aether.data.api.AetherApi
import com.aether.data.model.ChatMessage

class MessageRepository(private val api: AetherApi) {
    suspend fun fetchMessages(conversationId: String): List<ChatMessage> = api.listMessages(conversationId)
    suspend fun delete(messageId: String) = api.deleteMessage(messageId)
    suspend fun submitFeedback(messageId: String, isPositive: Boolean?, citations: List<String>? = null) =
        api.submitFeedback(messageId, isPositive, citations)
}
