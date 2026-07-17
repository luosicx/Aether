package com.aether.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.aether.data.db.AetherDatabase
import com.aether.data.db.ConversationDao
import com.aether.data.db.ConversationEntity
import com.aether.data.db.MessageDao
import com.aether.data.db.MessageEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * 数据访问层测试（Room DAO）。
 *
 * 注：ConversationRepository 实际使用 AetherApi（网络层），不直接使用 Room。
 * 此处测试 Room 数据访问层（ConversationDao / MessageDao）的 CRUD 与排序逻辑，
 * 使用 Room in-memory database。
 */
@RunWith(RobolectricTestRunner::class)
class ConversationRepositoryTest {

    private lateinit var db: AetherDatabase
    private lateinit var conversationDao: ConversationDao
    private lateinit var messageDao: MessageDao

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AetherDatabase::class.java).build()
        conversationDao = db.conversationDao()
        messageDao = db.messageDao()
    }

    @After
    fun close() {
        db.close()
    }

    private fun makeConversation(
        id: String,
        title: String = "T",
        updatedAt: Long = 0L,
        isPinned: Boolean = false,
        order: Int = 0
    ) = ConversationEntity(
        id = id,
        title = title,
        systemPrompt = "",
        parentId = null,
        createdAt = 0L,
        updatedAt = updatedAt,
        lastMessagePreview = "",
        isPinned = isPinned,
        unreadCount = 0,
        order = order
    )

    @Test
    fun insertAndGetConversationById() = runBlocking {
        val conv = makeConversation("c1", "First", updatedAt = 100L)
        conversationDao.upsert(conv)
        val fetched = conversationDao.getById("c1")
        assertNotNull(fetched)
        assertEquals("First", fetched!!.title)
    }

    @Test
    fun upsertReplacesExisting() = runBlocking {
        conversationDao.upsert(makeConversation("c1", "Old", updatedAt = 100L))
        conversationDao.upsert(makeConversation("c1", "New", updatedAt = 200L))
        val fetched = conversationDao.getById("c1")
        assertEquals("New", fetched!!.title)
        assertEquals(200L, fetched.updatedAt)
    }

    @Test
    fun deleteByIdRemovesConversation() = runBlocking {
        conversationDao.upsert(makeConversation("c1", "Temp", updatedAt = 100L))
        conversationDao.deleteById("c1")
        assertNull(conversationDao.getById("c1"))
    }

    @Test
    fun observeAllSortsByPinnedThenOrderThenUpdatedAt() = runBlocking {
        val c1 = makeConversation("c1", "C1", updatedAt = 100L, isPinned = false, order = 0)
        val c2 = makeConversation("c2", "C2", updatedAt = 50L, isPinned = true, order = 0)
        val c3 = makeConversation("c3", "C3", updatedAt = 200L, isPinned = false, order = 0)
        conversationDao.upsertAll(listOf(c1, c2, c3))

        val result = conversationDao.observeAll().first()
        assertEquals(3, result.size)
        // 排序：isPinned DESC → c2 先；然后 order ASC, updatedAt DESC → c3(200) > c1(100)
        assertEquals("c2", result[0].id)  // pinned
        assertEquals("c3", result[1].id)  // updatedAt=200
        assertEquals("c1", result[2].id)  // updatedAt=100
    }

    @Test
    fun observeAllEmptyWhenNoData() = runBlocking {
        val result = conversationDao.observeAll().first()
        assertTrue(result.isEmpty())
    }

    @Test
    fun insertAndGetMessageByConversation() = runBlocking {
        conversationDao.upsert(makeConversation("c1", "Conv", updatedAt = 100L))
        val msg = MessageEntity(
            id = "m1",
            conversationId = "c1",
            role = "user",
            content = "hello",
            toolCallsJson = null,
            toolCallId = null,
            toolName = null,
            feedback = null,
            createdAt = 100L
        )
        messageDao.upsert(msg)

        val messages = messageDao.observeByConversation("c1").first()
        assertEquals(1, messages.size)
        assertEquals("hello", messages[0].content)
    }

    @Test
    fun messagesOrderedByCreatedAtAsc() = runBlocking {
        conversationDao.upsert(makeConversation("c1", "Conv", updatedAt = 100L))
        messageDao.upsert(MessageEntity("m2", "c1", "assistant", "second", null, null, null, null, 200L))
        messageDao.upsert(MessageEntity("m1", "c1", "user", "first", null, null, null, null, 100L))

        val messages = messageDao.observeByConversation("c1").first()
        assertEquals(2, messages.size)
        assertEquals("m1", messages[0].id)  // createdAt=100 先
        assertEquals("m2", messages[1].id) // createdAt=200 后
    }

    @Test
    fun deleteByConversationRemovesAllMessages() = runBlocking {
        conversationDao.upsert(makeConversation("c1", "Conv", updatedAt = 100L))
        messageDao.upsert(MessageEntity("m1", "c1", "user", "a", null, null, null, null, 100L))
        messageDao.upsert(MessageEntity("m2", "c1", "assistant", "b", null, null, null, null, 200L))

        messageDao.deleteByConversation("c1")
        val messages = messageDao.observeByConversation("c1").first()
        assertTrue(messages.isEmpty())
    }
}
