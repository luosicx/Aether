package com.aether.data.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Model 类的 JSON 序列化/反序列化与默认值测试。
 */
class ModelsTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Test
    fun conversationRoundTripSerialization() {
        val conv = Conversation(
            id = "conv-1",
            title = "测试会话",
            systemPrompt = "你是助手",
            parentId = null,
            createdAt = 1700000000L,
            updatedAt = 1700000100L,
            lastMessagePreview = "预览",
            isPinned = true,
            unreadCount = 3,
            order = 1
        )
        val encoded = json.encodeToString(Conversation.serializer(), conv)
        val decoded = json.decodeFromString(Conversation.serializer(), encoded)
        assertEquals(conv, decoded)
    }

    @Test
    fun conversationDefaultsApplied() {
        val conv = Conversation(
            id = "c1",
            title = "T",
            createdAt = 0L,
            updatedAt = 0L
        )
        assertEquals("你是一个有帮助的AI助手。", conv.systemPrompt)
        assertNull(conv.parentId)
        assertEquals("", conv.lastMessagePreview)
        assertFalse(conv.isPinned)
        assertEquals(0, conv.unreadCount)
        assertEquals(0, conv.order)
    }

    @Test
    fun conversationDeserializesFromJsonWithDefaults() {
        val jsonString = """{"id":"c2","title":"X","createdAt":1,"updatedAt":2}"""
        val conv = json.decodeFromString(Conversation.serializer(), jsonString)
        assertEquals("c2", conv.id)
        assertEquals("你是一个有帮助的AI助手。", conv.systemPrompt)
        assertFalse(conv.isPinned)
        assertEquals(0, conv.unreadCount)
    }

    @Test
    fun chatMessageDefaults() {
        val msg = ChatMessage(
            id = "m1",
            conversationId = "c1",
            role = "user",
            content = "hello",
            createdAt = 0L
        )
        assertNull(msg.toolCalls)
        assertNull(msg.toolCallId)
        assertNull(msg.toolName)
        assertNull(msg.feedback)
    }

    @Test
    fun memorySerializationAndDefaults() {
        val mem = Memory(
            id = "mem-1",
            content = "用户偏好暗色主题",
            createdAt = 1700000000L
        )
        assertEquals("context", mem.category)
        assertEquals(0.5, mem.importance, 0.0001)

        val encoded = json.encodeToString(Memory.serializer(), mem)
        val decoded = json.decodeFromString(Memory.serializer(), encoded)
        assertEquals(mem, decoded)
        // 确认字段映射正确
        assertTrue(encoded.contains("\"content\":\"用户偏好暗色主题\""))
        assertTrue(encoded.contains("\"category\":\"context\""))
    }

    @Test
    fun chatRequestDefaults() {
        val req = ChatRequest(
            message = "hi",
            conversationId = "c1"
        )
        assertEquals("deepseek-chat", req.model)
        assertTrue(req.memoryEnabled)
    }

    @Test
    fun toolCallSerialization() {
        val tc = ToolCall(id = "tc1", name = "search", arguments = "{\"q\":\"test\"}")
        val encoded = json.encodeToString(ToolCall.serializer(), tc)
        val decoded = json.decodeFromString(ToolCall.serializer(), encoded)
        assertEquals(tc, decoded)
    }
}
