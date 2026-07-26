package com.aether.data.repository

import com.aether.data.api.AetherApi
import com.aether.data.db.MessageDao
import com.aether.data.db.MessageEntity
import com.aether.data.model.ChatMessage
import com.aether.data.model.ToolCall
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * 消息仓库：先 Room 后网络的实现模式。
 *
 * - `observeMessages(conversationId)`: 返回 Room 缓存的 Flow，UI 通过此订阅。
 * - `fetchMessages(conversationId)`: 一次性读取本地缓存，后台触发网络同步（向后兼容）。
 * - `delete(messageId)`: 先删 Room，再调 API；API 失败恢复本地。
 * - `submitFeedback(...)`: 直接走网络（无本地缓存需求）。
 *
 * @param api BFF API 客户端
 * @param dao 消息 DAO
 * @param syncManager 同步管理器（用于后台刷新）
 */
class MessageRepository(
    private val api: AetherApi,
    private val dao: MessageDao,
    private val syncManager: RepositorySyncManager
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }

    /**
     * 订阅指定会话下的消息列表（按 createdAt 升序）。
     */
    fun observeMessages(conversationId: String): Flow<List<ChatMessage>> =
        dao.observeByConversation(conversationId).map { entities -> entities.map { it.toModel() } }

    /**
     * 一次性获取消息列表：先返回本地缓存，后台异步同步网络数据。
     *
     * 向后兼容：保留与旧实现相同的方法签名。
     */
    suspend fun fetchMessages(conversationId: String): List<ChatMessage> {
        val local: List<ChatMessage> =
            dao.observeByConversation(conversationId).first().map { it.toModel() }
        // 后台触发网络同步
        syncManager.syncMessages(conversationId)
        // 同步可能已更新 Room，再次读取
        return dao.observeByConversation(conversationId).first().map { it.toModel() }
            .ifEmpty { local }
    }

    /**
     * 删除消息：先删 Room，再调 API；API 失败恢复本地。
     *
     * @param messageId 消息 ID
     * @throws Exception 网络失败时抛出，本地记录已恢复
     */
    suspend fun delete(messageId: String) {
        // 备份本地消息，API 失败时恢复
        val backup = dao.getById(messageId)
        dao.deleteById(messageId)
        try {
            api.deleteMessage(messageId)
        } catch (e: Exception) {
            // API 失败：恢复本地消息
            backup?.let { dao.upsert(it) }
            throw e
        }
    }

    /**
     * 提交消息反馈：直接走网络（无本地缓存需求，反馈为附加元数据）。
     */
    suspend fun submitFeedback(
        messageId: String,
        isPositive: Boolean?,
        citations: List<String>? = null
    ) = api.submitFeedback(messageId, isPositive, citations)

    // ===== Entity <-> Model 映射 =====

    private fun MessageEntity.toModel(): ChatMessage = ChatMessage(
        id = id,
        conversationId = conversationId,
        role = role,
        content = content,
        toolCalls = toolCallsJson?.takeIf { it.isNotEmpty() }?.let {
            runCatching {
                json.decodeFromString(ListSerializer(ToolCall.serializer()), it)
            }.getOrNull()
        },
        toolCallId = toolCallId,
        toolName = toolName,
        feedback = feedback,
        createdAt = createdAt
    )
}
