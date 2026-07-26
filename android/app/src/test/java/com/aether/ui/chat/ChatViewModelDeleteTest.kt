package com.aether.ui.chat

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.aether.data.api.AetherApi
import com.aether.data.api.BffConfig
import com.aether.data.api.ChatStreamClient
import com.aether.data.db.AetherDatabase
import com.aether.data.db.ConversationEntity
import com.aether.data.db.MessageEntity
import com.aether.data.model.ChatMessage
import com.aether.data.repository.MessageRepository
import com.aether.data.repository.RepositorySyncManager
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
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
 * ChatViewModel 删除 / 重发消息 单元测试。
 *
 * 使用 ktor MockEngine 模拟 BFF 响应：
 * - GET /conversations/{id}/messages 预置消息列表
 * - DELETE /messages/{id} 用于删除消息
 * - POST /chat/stream 用于流式发送（测试中 SSE 立即 [DONE]）
 *
 * 使用 Room in-memory database 验证「先 Room 后网络」的删除路径。
 *
 * 关键点：
 * - ktor-client-mock 2.3.12 起 MockEngine 默认使用 `Dispatchers.IO` 执行请求，
 *   Room 查询也走 `Dispatchers.IO`。`runTest` + `advanceUntilIdle` 无法等待真实
 *   IO 线程完成，因此改用 `runBlocking` + `Dispatchers.Unconfined`。
 * - 通过 [awaitMessageCount] / [awaitError] 轮询 ViewModel 状态等待协程完成。
 */
@RunWith(RobolectricTestRunner::class)
class ChatViewModelDeleteTest {

    private lateinit var db: AetherDatabase

    @Before
    fun setMainDispatcher() {
        // Dispatchers.Unconfined 使 viewModelScope 协程立即启动；
        // ktor/Room 内部 withContext(Dispatchers.IO) 会切换到真实 IO 线程，
        // 完成后协程在恢复线程上继续执行（Unconfined 语义）。
        Dispatchers.setMain(Dispatchers.Unconfined)
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AetherDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun resetMainDispatcher() {
        Dispatchers.resetMain()
        db.close()
    }

    /**
     * 构造用户消息。`createdAt` 必须由调用方指定以保证 Room 排序确定性
     * （MessageDao 按 `createdAt ASC` 排序，重复时间戳会导致非确定性顺序）。
     */
    private fun userMessage(
        id: String,
        content: String,
        conversationId: String = "c1",
        createdAt: Long
    ): ChatMessage =
        ChatMessage(
            id = id,
            conversationId = conversationId,
            role = "user",
            content = content,
            createdAt = createdAt
        )

    /**
     * 构造助手消息。`createdAt` 必须由调用方指定以保证 Room 排序确定性。
     */
    private fun assistantMessage(
        id: String,
        content: String,
        conversationId: String = "c1",
        createdAt: Long
    ): ChatMessage =
        ChatMessage(
            id = id,
            conversationId = conversationId,
            role = "assistant",
            content = content,
            createdAt = createdAt
        )

    private fun jsonMessages(messages: List<ChatMessage>): String =
        Json.encodeToString(ListSerializer(ChatMessage.serializer()), messages)

    private suspend fun seedRoom(initialMessages: List<ChatMessage>) {
        // 先写入会话，再批量写入消息
        db.conversationDao().upsert(
            ConversationEntity(
                id = "c1",
                title = "Test",
                systemPrompt = "",
                parentId = null,
                createdAt = 0L,
                updatedAt = 0L,
                lastMessagePreview = "",
                isPinned = false,
                unreadCount = 0,
                order = 0
            )
        )
        initialMessages.forEach { m ->
            db.messageDao().upsert(
                MessageEntity(
                    id = m.id,
                    conversationId = m.conversationId,
                    role = m.role,
                    content = m.content,
                    toolCallsJson = null,
                    toolCallId = null,
                    toolName = null,
                    feedback = null,
                    createdAt = m.createdAt
                )
            )
        }
    }

    private fun apiHandlingMessages(
        initialMessages: List<ChatMessage>,
        deleteFails: Boolean = false
    ): AetherApi {
        val client = HttpClient(MockEngine { requestData ->
            val path = requestData.url.encodedPath
            when {
                requestData.method.value == "GET" && path.contains("/messages") ->
                    respond(
                        content = jsonMessages(initialMessages),
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json")
                    )
                requestData.method.value == "DELETE" && path.contains("/messages/") -> {
                    if (deleteFails) {
                        // 模拟网络异常（ktor 默认不抛非 2xx，需抛异常才能被 ViewModel 捕获）
                        throw RuntimeException("Network error")
                    } else {
                        respond("", HttpStatusCode.OK)
                    }
                }
                else -> respond("", HttpStatusCode.OK)
            }
        }) {
            install(ContentNegotiation) { json() }
        }
        return AetherApi(client, BffConfig(baseUrl = "http://test", userToken = "tok"))
    }

    private fun streamClientReturningDone(): ChatStreamClient {
        val client = HttpClient(MockEngine { _ ->
            respond(
                content = "data: [DONE]\n\n",
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "text/event-stream")
            )
        }) {
            install(ContentNegotiation) { json() }
        }
        return ChatStreamClient(client, BffConfig(baseUrl = "http://test", userToken = "tok"))
    }

    private fun buildRepo(api: AetherApi): MessageRepository {
        val syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        return MessageRepository(api, db.messageDao(), syncManager)
    }

    /**
     * 等待 ChatViewModel 的 `messages` 列表大小达到预期值。
     *
     * `loadMessages` / `deleteMessage` 等方法通过 `viewModelScope.launch` 异步更新
     * `messages`。由于 ktor/Room 走真实 `Dispatchers.IO`，无法用 `advanceUntilIdle`
     * 等待，改用轮询 `messages.value.size` 直到满足条件或超时。
     */
    private suspend fun awaitMessageCount(vm: ChatViewModel, expected: Int) {
        val deadline = System.currentTimeMillis() + 2000L
        while (vm.messages.value.size != expected && System.currentTimeMillis() < deadline) {
            delay(10)
        }
    }

    /**
     * 等待 ChatViewModel 设置错误信息。
     *
     * `deleteMessage` 在 API 失败时设置 `errorMessage`。轮询直到 `errorMessage` 非空或超时。
     */
    private suspend fun awaitError(vm: ChatViewModel) {
        val deadline = System.currentTimeMillis() + 2000L
        while (vm.errorMessage.value == null && System.currentTimeMillis() < deadline) {
            delay(10)
        }
    }

    /**
     * 等待条件满足或超时。
     *
     * 用于轮询 `streamRequested` 等外部标志位（在 MockEngine handler 中设置，
     * handler 走 `Dispatchers.IO`）。
     */
    private suspend fun awaitCondition(condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 2000L
        while (!condition() && System.currentTimeMillis() < deadline) {
            delay(10)
        }
    }

    @Test
    fun deleteMessageRemovesFromListOnApiSuccess() = runBlocking {
        val initial = listOf(
            userMessage("m1", "hello", createdAt = 1000L),
            assistantMessage("m2", "hi there", createdAt = 2000L),
            userMessage("m3", "bye", createdAt = 3000L)
        )
        seedRoom(initial)
        val api = apiHandlingMessages(initial)
        val repo = buildRepo(api)
        val vm = ChatViewModel(streamClientReturningDone(), repo)
        vm.loadMessages("c1")
        awaitMessageCount(vm, 3)  // 等待 loadMessages 协程完成

        vm.deleteMessage("m2")
        awaitMessageCount(vm, 2)  // 等待 deleteMessage 协程完成

        val remaining = vm.messages.value
        assertEquals(2, remaining.size)
        assertTrue(remaining.none { it.id == "m2" })
        // 不应设置错误
        assertNull(vm.errorMessage.value)
    }

    @Test
    fun deleteMessageSetsErrorOnApiFailure() = runBlocking {
        val initial = listOf(userMessage("m1", "hello", createdAt = 1000L))
        seedRoom(initial)
        val api = apiHandlingMessages(
            initialMessages = initial,
            deleteFails = true
        )
        val repo = buildRepo(api)
        val vm = ChatViewModel(streamClientReturningDone(), repo)
        vm.loadMessages("c1")
        awaitMessageCount(vm, 1)

        vm.deleteMessage("m1")
        awaitError(vm)  // 等待 errorMessage 设置

        // API 失败时消息已被本地删除（依赖下次 syncMessages 恢复）
        val msg = vm.errorMessage.value
        assertNotNull("应设置错误信息", msg)
        assertTrue("错误信息应包含「删除消息失败」: $msg", msg!!.contains("删除消息失败"))
    }

    @Test
    fun resendMessageRemovesSubsequentMessagesAndResends() = runBlocking {
        var streamRequested = false
        val streamClient = ChatStreamClient(
            HttpClient(MockEngine { _ ->
                streamRequested = true
                respond(
                    content = "data: [DONE]\n\n",
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "text/event-stream")
                )
            }) { install(ContentNegotiation) { json() } },
            BffConfig(baseUrl = "http://test", userToken = "tok")
        )
        val initial = listOf(
            userMessage("u1", "first", createdAt = 1000L),
            assistantMessage("a1", "resp1", createdAt = 2000L),
            userMessage("u2", "second", createdAt = 3000L),
            assistantMessage("a2", "resp2", createdAt = 4000L)
        )
        seedRoom(initial)
        val api = apiHandlingMessages(initial)
        val repo = buildRepo(api)
        val vm = ChatViewModel(streamClient, repo)
        vm.loadMessages("c1")
        awaitMessageCount(vm, 4)

        vm.resendMessage(initial[2]) // 重发 "u2"
        awaitCondition { streamRequested }  // 等待流式请求发起

        assertTrue("应发起流式请求", streamRequested)
        val current = vm.messages.value
        // u2 之前的消息保留 + u2 重发后的新消息；a2 应被移除
        assertTrue("u1 应保留: ${current.map { it.id }}", current.any { it.id == "u1" })
        assertTrue("a1 应保留: ${current.map { it.id }}", current.any { it.id == "a1" })
        assertTrue("a2 应被移除: ${current.map { it.id }}", current.none { it.id == "a2" })
        // u2 在重发列表中（同 ID）
        assertTrue("u2 应在列表中: ${current.map { it.id }}", current.any { it.id == "u2" })
    }

    @Test
    fun resendMessageIgnoresAssistantMessage() = runBlocking {
        var streamRequested = false
        val streamClient = ChatStreamClient(
            HttpClient(MockEngine { _ ->
                streamRequested = true
                respond("data: [DONE]\n\n", HttpStatusCode.OK,
                    headersOf(HttpHeaders.ContentType, "text/event-stream"))
            }) { install(ContentNegotiation) { json() } },
            BffConfig(baseUrl = "http://test", userToken = "tok")
        )
        val initial = listOf(
            userMessage("u1", "first", createdAt = 1000L),
            assistantMessage("a1", "resp1", createdAt = 2000L)
        )
        seedRoom(initial)
        val api = apiHandlingMessages(initial)
        val repo = buildRepo(api)
        val vm = ChatViewModel(streamClient, repo)
        vm.loadMessages("c1")
        awaitMessageCount(vm, 2)
        val original = vm.messages.value
        assertEquals(2, original.size)

        // 重发 assistant 消息应直接返回，不触发流式
        vm.resendMessage(original[1])
        assertFalse("不应发起流式请求", streamRequested)
        assertEquals(original, vm.messages.value)
    }
}
