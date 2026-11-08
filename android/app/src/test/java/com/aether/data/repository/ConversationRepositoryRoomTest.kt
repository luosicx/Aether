package com.aether.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.aether.data.api.AetherApi
import com.aether.data.api.BffConfig
import com.aether.data.db.AetherDatabase
import com.aether.data.model.Conversation
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * ConversationRepository「先 Room 后网络」模式测试。
 *
 * 覆盖：
 * - fetchAll：本地缓存优先，触发后台同步
 * - create：先写 Room 再调 API，API 失败回滚本地
 * - delete：先删 Room 再调 API，API 失败恢复本地
 * - update：先更新 Room 再调 API，API 失败保留乐观更新
 * - observeAll：返回 Room Flow，UI 订阅实时更新
 */
@RunWith(RobolectricTestRunner::class)
class ConversationRepositoryRoomTest {

    private lateinit var db: AetherDatabase
    private lateinit var api: AetherApi
    private lateinit var repo: ConversationRepository
    private lateinit var syncManager: RepositorySyncManager

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AetherDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun close() {
        db.close()
    }

    /**
     * 构造一个 MockEngine 驱动的 AetherApi，按 [behavior] 决定响应行为。
     *
     * @param behavior 网络行为：success 正常返回，createFails / deleteFails / updateFails / listFails 抛异常
     * @param listPayload GET /conversations 返回的会话列表
     */
    private fun buildApi(
        behavior: MockBehavior = MockBehavior.SUCCESS,
        listPayload: List<Conversation> = emptyList()
    ): AetherApi {
        val client = HttpClient(MockEngine { requestData ->
            val path = requestData.url.encodedPath
            val method = requestData.method.value
            when {
                method == "GET" && path.endsWith("/conversations") -> {
                    if (behavior == MockBehavior.LIST_FAILS) {
                        throw RuntimeException("network error")
                    }
                    val json = Json.encodeToString(
                        ListSerializer(Conversation.serializer()),
                        listPayload
                    )
                    respond(
                        content = json,
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                }
                method == "POST" && path.endsWith("/conversations") -> {
                    if (behavior == MockBehavior.CREATE_FAILS) {
                        throw RuntimeException("create failed")
                    }
                    // 返回一个服务端生成的 Conversation
                    val response = Conversation(
                        id = "server-${System.currentTimeMillis()}",
                        title = "Server Conv",
                        createdAt = 0L,
                        updatedAt = 0L
                    )
                    respond(
                        content = Json.encodeToString(Conversation.serializer(), response),
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                }
                method == "DELETE" && path.contains("/conversations/") -> {
                    if (behavior == MockBehavior.DELETE_FAILS) {
                        throw RuntimeException("delete failed")
                    }
                    respond("", HttpStatusCode.OK)
                }
                method == "PATCH" && path.contains("/conversations/") -> {
                    if (behavior == MockBehavior.UPDATE_FAILS) {
                        throw RuntimeException("update failed")
                    }
                    // 返回更新后的会话（标题加 server 后缀以区分）
                    val response = Conversation(
                        id = "c1",
                        title = "Server Updated",
                        createdAt = 0L,
                        updatedAt = 1000L,
                        isPinned = true
                    )
                    respond(
                        content = Json.encodeToString(Conversation.serializer(), response),
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                }
                else -> respond("", HttpStatusCode.OK)
            }
        }) {
            install(ContentNegotiation) { json() }
        }
        return AetherApi(client, BffConfig(baseUrl = "http://test", userToken = "tok"))
    }

    private fun makeConversation(
        id: String,
        title: String = "Conv",
        updatedAt: Long = 0L,
        isPinned: Boolean = false
    ) = Conversation(
        id = id,
        title = title,
        createdAt = 0L,
        updatedAt = updatedAt,
        isPinned = isPinned
    )

    private enum class MockBehavior {
        SUCCESS, CREATE_FAILS, DELETE_FAILS, UPDATE_FAILS, LIST_FAILS
    }

    @Test
    fun fetchAllReturnsLocalCacheWhenNetworkSucceeds() = runTest {
        // 预置本地数据
        val localConv = makeConversation("local-1", "Local Conv")
        db.conversationDao().upsert(localConv.let {
            com.aether.data.db.ConversationEntity(
                id = it.id, title = it.title, systemPrompt = "", parentId = null,
                createdAt = it.createdAt, updatedAt = it.updatedAt,
                lastMessagePreview = "", isPinned = it.isPinned, unreadCount = 0, order = 0
            )
        })
        // 服务端返回另一条
        val remoteConv = makeConversation("remote-1", "Remote Conv")
        api = buildApi(behavior = MockBehavior.SUCCESS, listPayload = listOf(remoteConv))
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        val result = repo.fetchAll()
        // 同步后应包含本地 + 远程
        assertTrue("应包含本地 local-1", result.any { it.id == "local-1" })
        assertTrue("应包含远程 remote-1", result.any { it.id == "remote-1" })
    }

    @Test
    fun fetchAllFallsBackToLocalWhenNetworkFails() = runTest {
        val localConv = makeConversation("local-1", "Local Conv")
        db.conversationDao().upsert(
            com.aether.data.db.ConversationEntity(
                id = localConv.id, title = localConv.title, systemPrompt = "",
                parentId = null, createdAt = 0L, updatedAt = 0L,
                lastMessagePreview = "", isPinned = false, unreadCount = 0, order = 0
            )
        )
        api = buildApi(behavior = MockBehavior.LIST_FAILS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        val result = repo.fetchAll()
        // 网络失败应保留本地
        assertEquals(1, result.size)
        assertEquals("local-1", result[0].id)
    }

    @Test
    fun createWritesRoomThenApiReplacesTempId() = runTest {
        api = buildApi(behavior = MockBehavior.SUCCESS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        val created = repo.create("New Conversation")
        // 应返回服务端生成的 ID（以 "server-" 开头）
        assertTrue("应使用服务端 ID: ${created.id}", created.id.startsWith("server-"))
        // Room 中不应残留临时 ID（"local-" 开头）
        val all = repo.observeAll().first()
        assertTrue("Room 中不应有临时记录", all.none { it.id.startsWith("local-") })
        assertTrue("Room 中应有服务端记录", all.any { it.id == created.id })
    }

    @Test
    fun createRollsBackRoomOnApiFailure() = runTest {
        api = buildApi(behavior = MockBehavior.CREATE_FAILS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        var threw = false
        try {
            repo.create("Will Fail")
        } catch (e: Exception) {
            threw = true
        }
        assertTrue("API 失败应抛异常", threw)
        // Room 应已回滚，无临时记录
        val all = repo.observeAll().first()
        assertTrue("Room 应为空（已回滚）", all.isEmpty())
    }

    @Test
    fun deleteRemovesFromRoomOnApiSuccess() = runTest {
        db.conversationDao().upsert(
            com.aether.data.db.ConversationEntity(
                id = "c1", title = "Conv", systemPrompt = "",
                parentId = null, createdAt = 0L, updatedAt = 0L,
                lastMessagePreview = "", isPinned = false, unreadCount = 0, order = 0
            )
        )
        api = buildApi(behavior = MockBehavior.SUCCESS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        repo.delete("c1")
        assertNull("Room 中应已删除", db.conversationDao().getById("c1"))
    }

    @Test
    fun deleteRestoresRoomOnApiFailure() = runTest {
        db.conversationDao().upsert(
            com.aether.data.db.ConversationEntity(
                id = "c1", title = "Conv", systemPrompt = "",
                parentId = null, createdAt = 0L, updatedAt = 0L,
                lastMessagePreview = "", isPinned = false, unreadCount = 0, order = 0
            )
        )
        api = buildApi(behavior = MockBehavior.DELETE_FAILS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        var threw = false
        try {
            repo.delete("c1")
        } catch (e: Exception) {
            threw = true
        }
        assertTrue("API 失败应抛异常", threw)
        // Room 应已恢复
        val restored = db.conversationDao().getById("c1")
        assertNotNull("Room 应已恢复", restored)
        assertEquals("c1", restored!!.id)
    }

    @Test
    fun updateAppliesOptimisticLocalChangeOnApiSuccess() = runTest {
        db.conversationDao().upsert(
            com.aether.data.db.ConversationEntity(
                id = "c1", title = "Old Title", systemPrompt = "",
                parentId = null, createdAt = 0L, updatedAt = 0L,
                lastMessagePreview = "", isPinned = false, unreadCount = 0, order = 0
            )
        )
        api = buildApi(behavior = MockBehavior.SUCCESS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        val updated = repo.update("c1", isPinned = true)
        // API 成功：使用服务端返回值
        assertTrue("应反映服务端 isPinned=true", updated.isPinned)
        // Room 也应被更新
        val roomRecord = db.conversationDao().getById("c1")
        assertNotNull(roomRecord)
        assertTrue("Room 中 isPinned 应为 true", roomRecord!!.isPinned)
    }

    @Test
    fun updateKeepsOptimisticLocalChangeOnApiFailure() = runTest {
        db.conversationDao().upsert(
            com.aether.data.db.ConversationEntity(
                id = "c1", title = "Old Title", systemPrompt = "",
                parentId = null, createdAt = 0L, updatedAt = 0L,
                lastMessagePreview = "", isPinned = false, unreadCount = 0, order = 0
            )
        )
        api = buildApi(behavior = MockBehavior.UPDATE_FAILS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        val updated = repo.update("c1", isPinned = true)
        // API 失败：返回乐观更新值（本地状态）
        assertTrue("应返回乐观更新的 isPinned=true", updated.isPinned)
        // Room 保留乐观更新
        val roomRecord = db.conversationDao().getById("c1")
        assertNotNull(roomRecord)
        assertTrue("Room 中应保留乐观更新 isPinned=true", roomRecord!!.isPinned)
    }

    @Test
    fun observeAllEmitsRoomChanges() = runTest {
        api = buildApi(behavior = MockBehavior.SUCCESS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        repo = ConversationRepository(api, db.conversationDao(), syncManager)

        // 初始为空
        val initial = repo.observeAll().first()
        assertTrue("初始应为空", initial.isEmpty())

        // 写入 Room 后 Flow 应反映
        db.conversationDao().upsert(
            com.aether.data.db.ConversationEntity(
                id = "c1", title = "First", systemPrompt = "",
                parentId = null, createdAt = 0L, updatedAt = 0L,
                lastMessagePreview = "", isPinned = false, unreadCount = 0, order = 0
            )
        )
        val afterInsert = repo.observeAll().first()
        assertEquals(1, afterInsert.size)
        assertEquals("c1", afterInsert[0].id)

        // 删除后 Flow 应反映
        db.conversationDao().deleteById("c1")
        val afterDelete = repo.observeAll().first()
        assertTrue("删除后应为空", afterDelete.isEmpty())
    }

    @Test
    fun syncManagerSyncConversationsPersistsRemoteToRoom() = runTest {
        val remoteConv = makeConversation("remote-1", "Remote")
        api = buildApi(behavior = MockBehavior.SUCCESS, listPayload = listOf(remoteConv))
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())

        syncManager.syncConversations()
        val all = db.conversationDao().observeAll().first()
        assertTrue("Room 应包含远程同步的记录", all.any { it.id == "remote-1" })
    }

    @Test
    fun syncManagerSyncConversationsKeepsLocalOnNetworkFailure() = runTest {
        // 预置本地
        db.conversationDao().upsert(
            com.aether.data.db.ConversationEntity(
                id = "local-1", title = "Local", systemPrompt = "",
                parentId = null, createdAt = 0L, updatedAt = 0L,
                lastMessagePreview = "", isPinned = false, unreadCount = 0, order = 0
            )
        )
        api = buildApi(behavior = MockBehavior.LIST_FAILS)
        syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())

        // 同步失败不应抛异常
        syncManager.syncConversations()
        val all = db.conversationDao().observeAll().first()
        assertEquals("网络失败应保留本地数据", 1, all.size)
        assertEquals("local-1", all[0].id)
    }
}
