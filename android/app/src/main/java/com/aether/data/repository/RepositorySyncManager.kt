package com.aether.data.repository

import android.util.Log
import com.aether.data.api.AetherApi
import com.aether.data.db.ConversationDao
import com.aether.data.db.ConversationEntity
import com.aether.data.db.MessageDao
import com.aether.data.db.MessageEntity
import com.aether.data.model.ChatMessage
import com.aether.data.model.Conversation
import com.aether.data.model.ToolCall
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * 仓库同步管理器：协调 Room 与网络的双向同步。
 *
 * 同步策略：
 * - 拉取优先：从 BFF 拉取最新数据，覆盖写入 Room（保留本地乐观更新未同步的记录）。
 * - 错误容忍：网络失败时仅记录日志，**不抛异常**，保留本地缓存供下次重试。
 *
 * 所有同步操作在 IO 调度器上执行；调用方可在任何调度器上调用。
 *
 * @param api BFF API 客户端
 * @param conversationDao 会话 DAO
 * @param messageDao 消息 DAO
 */
class RepositorySyncManager(
    private val api: AetherApi,
    private val conversationDao: ConversationDao,
    private val messageDao: MessageDao
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }

    /**
     * 同步所有会话：从 BFF 拉取最新列表，覆盖 Room。
     *
     * 网络失败时保留本地数据，仅记录日志。
     */
    suspend fun syncConversations() = withContext(Dispatchers.IO) {
        try {
            val remote: List<Conversation> = api.listConversations()
            val entities = remote.map { it.toEntity() }
            if (entities.isNotEmpty()) {
                conversationDao.upsertAll(entities)
            }
            Unit
        } catch (e: Exception) {
            Log.w(TAG, "syncConversations: 网络同步失败，保留本地数据", e)
        }
    }

    /**
     * 同步指定会话下的消息：从 BFF 拉取最新消息列表，覆盖 Room。
     *
     * 网络失败时保留本地数据，仅记录日志。
     *
     * @param conversationId 会话 ID
     */
    suspend fun syncMessages(conversationId: String) = withContext(Dispatchers.IO) {
        try {
            val remote: List<ChatMessage> = api.listMessages(conversationId)
            val entities = remote.map { it.toEntity() }
            if (entities.isNotEmpty()) {
                messageDao.upsertAll(entities)
            }
            Unit
        } catch (e: Exception) {
            Log.w(TAG, "syncMessages($conversationId): 网络同步失败，保留本地数据", e)
        }
    }

    /**
     * Conversation -> ConversationEntity 映射（与 Repository 中保持一致）。
     */
    private fun Conversation.toEntity(): ConversationEntity = ConversationEntity(
        id = id,
        title = title,
        systemPrompt = systemPrompt,
        parentId = parentId,
        createdAt = createdAt,
        updatedAt = updatedAt,
        lastMessagePreview = lastMessagePreview,
        isPinned = isPinned,
        unreadCount = unreadCount,
        order = order
    )

    /**
     * ChatMessage -> MessageEntity 映射：toolCalls 序列化为 JSON 字符串存储。
     */
    private fun ChatMessage.toEntity(): MessageEntity = MessageEntity(
        id = id,
        conversationId = conversationId,
        role = role,
        content = content,
        toolCallsJson = toolCalls?.takeIf { it.isNotEmpty() }?.let {
            json.encodeToString(ListSerializer(ToolCall.serializer()), it)
        },
        toolCallId = toolCallId,
        toolName = toolName,
        feedback = feedback,
        createdAt = createdAt
    )

    private companion object {
        private const val TAG = "RepositorySyncManager"
    }
}
