package com.aether.data.repository

import com.aether.data.api.AetherApi
import com.aether.data.db.ConversationDao
import com.aether.data.db.ConversationEntity
import com.aether.data.model.Conversation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first
import java.util.UUID

/**
 * 会话仓库：先 Room 后网络的实现模式。
 *
 * - `observeAll()`: 返回 Room 缓存的 Flow，UI 通过此订阅实时更新；调用方可主动触发 [RepositorySyncManager.syncConversations] 后台同步。
 * - `fetchAll()`: 一次性读取本地缓存，并在后台触发网络同步（向后兼容 ViewModel 旧调用）。
 * - `create(title)`: 先写入 Room（临时 ID），再调用 API；API 失败回滚本地。
 * - `delete(id)`: 先删除 Room，再调用 API；API 失败恢复本地。
 * - `update(...)`: 先更新 Room（乐观更新），再调用 API；API 失败保留本地乐观状态，下次 [RepositorySyncManager.syncConversations] 时与服务端对齐。
 *
 * @param api BFF API 客户端
 * @param dao 会话 DAO
 * @param syncManager 同步管理器（用于后台刷新）
 */
class ConversationRepository(
    private val api: AetherApi,
    private val dao: ConversationDao,
    private val syncManager: RepositorySyncManager
) {
    /**
     * 订阅本地缓存的会话列表（按 isPinned / order / updatedAt 排序）。
     *
     * UI 通过此 Flow 实时更新；网络同步由调用方在合适时机触发 [RepositorySyncManager.syncConversations]。
     */
    fun observeAll(): Flow<List<Conversation>> =
        dao.observeAll().map { entities -> entities.map { it.toModel() } }

    /**
     * 一次性获取会话列表：先返回本地缓存，后台异步同步网络数据。
     *
     * 向后兼容：保留与旧实现相同的方法签名（返回 List 而非 Flow）。
     */
    suspend fun fetchAll(): List<Conversation> {
        val local: List<Conversation> = dao.observeAll().first().map { it.toModel() }
        // 后台触发网络同步，不阻塞当前调用
        syncManager.syncConversations()
        // 同步可能已更新 Room，再次读取以反映最新状态
        return dao.observeAll().first().map { it.toModel() }.ifEmpty { local }
    }

    /**
     * 创建会话：先写 Room（临时 UUID），再调 API；API 失败回滚本地。
     *
     * @param title 会话标题
     * @return 服务端返回的 Conversation（含最终 ID）
     * @throws Exception 网络失败时抛出，本地临时记录已回滚
     */
    suspend fun create(title: String): Conversation {
        val now = System.currentTimeMillis()
        val tempId = "local-${UUID.randomUUID()}"
        val tempEntity = ConversationEntity(
            id = tempId,
            title = title,
            systemPrompt = "",
            parentId = null,
            createdAt = now,
            updatedAt = now,
            lastMessagePreview = "",
            isPinned = false,
            unreadCount = 0,
            order = 0
        )
        // 先写本地
        dao.upsert(tempEntity)
        return try {
            val remote = api.createConversation(title)
            // 用服务端返回的实体替换临时实体
            dao.deleteById(tempId)
            dao.upsert(remote.toEntity())
            remote
        } catch (e: Exception) {
            // API 失败：回滚本地
            dao.deleteById(tempId)
            throw e
        }
    }

    /**
     * 删除会话：先删 Room，再调 API；API 失败恢复本地。
     *
     * @param id 会话 ID
     * @throws Exception 网络失败时抛出，本地记录已恢复
     */
    suspend fun delete(id: String) {
        val backup = dao.getById(id)
        dao.deleteById(id)
        try {
            api.deleteConversation(id)
        } catch (e: Exception) {
            // API 失败：恢复本地
            backup?.let { dao.upsert(it) }
            throw e
        }
    }

    /**
     * 更新会话：先更新 Room（乐观更新），再调 API；API 失败保留本地乐观状态。
     *
     * @param id 会话 ID
     * @param title 新标题（null 表示不修改）
     * @param isPinned 新置顶状态（null 表示不修改）
     * @return 更新后的 Conversation（API 成功则用服务端返回值，失败则用本地乐观更新值）
     */
    suspend fun update(id: String, title: String? = null, isPinned: Boolean? = null): Conversation {
        val current = dao.getById(id)
            ?: return api.updateConversation(id, title, isPinned)

        // 乐观更新本地
        val updatedEntity = current.copy(
            title = title ?: current.title,
            isPinned = isPinned ?: current.isPinned,
            updatedAt = System.currentTimeMillis()
        )
        dao.upsert(updatedEntity)

        return try {
            val remote = api.updateConversation(id, title, isPinned)
            dao.upsert(remote.toEntity())
            remote
        } catch (e: Exception) {
            // API 失败：保留本地乐观更新，下次 syncConversations 时与服务端对齐
            updatedEntity.toModel()
        }
    }

    // ===== Entity <-> Model 映射 =====

    private fun ConversationEntity.toModel(): Conversation = Conversation(
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
}
