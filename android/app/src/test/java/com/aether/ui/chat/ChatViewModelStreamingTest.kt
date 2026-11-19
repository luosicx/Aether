package com.aether.ui.chat

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.aether.data.api.AetherApi
import com.aether.data.api.BffConfig
import com.aether.data.api.ChatStreamSource
import com.aether.data.db.AetherDatabase
import com.aether.data.repository.MessageRepository
import com.aether.data.repository.RepositorySyncManager
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respondOk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * 流式文本节流测试。
 *
 * 节流器用注入的假时钟做纯逻辑断言；ChatViewModel 侧只验证接线：
 * 窗口内的增量不会丢，流结束时完整内容进入助手消息。
 * 真实 SSE 解析走 Rust JNI（JVM 测试无 .so），因此用 [ChatStreamSource] 注入固定增量序列。
 */
class StreamingTextThrottlerTest {
    private var now = 1_000_000L

    @Test
    fun firstChunkReturnsSnapshotImmediately() {
        val throttler = StreamingTextThrottler(nowNanos = { now })
        assertEquals("你", throttler.append("你"))
    }

    @Test
    fun chunksWithinWindowAreMerged() {
        val throttler = StreamingTextThrottler(nowNanos = { now })
        assertEquals("你", throttler.append("你"))
        now += 10_000_000L
        assertNull(throttler.append("好"))
        now += 10_000_000L
        assertNull(throttler.append("！"))
        assertEquals("你好！", throttler.flush())
    }

    @Test
    fun chunkAfterWindowReturnsCumulativeSnapshot() {
        val throttler = StreamingTextThrottler(nowNanos = { now })
        assertEquals("你", throttler.append("你"))
        now += StreamingTextThrottler.DEFAULT_INTERVAL_NANOS
        assertEquals("你好", throttler.append("好"))
    }

    @Test
    fun flushIncludesTailNotYetEmitted() {
        val throttler = StreamingTextThrottler(nowNanos = { now })
        throttler.append("a")
        now += 1
        assertNull(throttler.append("b"))
        assertEquals("ab", throttler.flush())
    }
}

@RunWith(RobolectricTestRunner::class)
class ChatViewModelStreamingTest {
    private lateinit var db: AetherDatabase

    @Before
    fun setMainDispatcher() {
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

    private fun buildViewModel(source: ChatStreamSource, nowNanos: () -> Long): ChatViewModel {
        val client = HttpClient(MockEngine { respondOk("") })
        val api = AetherApi(client, BffConfig(baseUrl = "http://test", userToken = "tok"))
        val syncManager = RepositorySyncManager(api, db.conversationDao(), db.messageDao())
        val repo = MessageRepository(api, db.messageDao(), syncManager)
        return ChatViewModel(source, repo, nowNanos)
    }

    private suspend fun awaitAssistantMessage(vm: ChatViewModel) {
        val deadline = System.currentTimeMillis() + 2000L
        while (vm.messages.value.none { it.role == "assistant" } && System.currentTimeMillis() < deadline) {
            delay(10)
        }
    }

    @Test
    fun throttledStreamKeepsFullContentInAssistantMessage() = runBlocking {
        // 时钟不前进：窗口内的增量不刷新 UI，但完整内容不能丢
        val vm = buildViewModel(ChatStreamSource { _ -> flowOf("你", "好", "！") }) { 0L }
        vm.currentConversationId = "c1"

        vm.send("hi")
        awaitAssistantMessage(vm)

        val assistant = vm.messages.value.firstOrNull { it.role == "assistant" }
        assertNotNull("应生成助手消息", assistant)
        assertEquals("你好！", assistant!!.content)
        assertNull(vm.errorMessage.value)
    }
}
