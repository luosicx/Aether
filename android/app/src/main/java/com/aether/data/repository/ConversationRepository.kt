package com.aether.data.repository

import com.aether.data.api.AetherApi
import com.aether.data.model.Conversation

class ConversationRepository(private val api: AetherApi) {
    suspend fun fetchAll(): List<Conversation> = api.listConversations()
    suspend fun create(title: String): Conversation = api.createConversation(title)
    suspend fun delete(id: String) = api.deleteConversation(id)
    suspend fun update(id: String, title: String? = null, isPinned: Boolean? = null): Conversation =
        api.updateConversation(id, title, isPinned)
}
