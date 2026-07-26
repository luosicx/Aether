package com.aether.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aether.data.api.ChatStreamClient
import com.aether.data.model.ChatMessage
import com.aether.data.model.ChatRequest
import com.aether.data.repository.MessageRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.util.UUID

class ChatViewModel(
    private val chatClient: ChatStreamClient,
    private val messageRepo: MessageRepository
) : ViewModel() {
    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _streamingText = MutableStateFlow("")
    val streamingText: StateFlow<String> = _streamingText.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    var currentConversationId: String? = null

    fun loadMessages(conversationId: String) {
        currentConversationId = conversationId
        viewModelScope.launch {
            try {
                _messages.value = messageRepo.fetchMessages(conversationId)
            } catch (e: Exception) {
                _errorMessage.value = "加载消息失败：${e.message}"
            }
        }
    }

    fun send(text: String) {
        val conversationId = currentConversationId ?: return
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val userMessage = ChatMessage(
            id = UUID.randomUUID().toString(),
            conversationId = conversationId,
            role = "user",
            content = trimmed,
            createdAt = System.currentTimeMillis()
        )
        _messages.update { it + userMessage }
        streamSend(userMessage)
    }

    /**
     * 内部流式发送：基于已有的用户消息发起 LLM 请求并追加助手回复。
     */
    private fun streamSend(userMessage: ChatMessage) {
        val conversationId = currentConversationId ?: return
        _isLoading.value = true
        _streamingText.value = ""
        _errorMessage.value = null

        viewModelScope.launch {
            try {
                val request = ChatRequest(
                    message = userMessage.content,
                    conversationId = conversationId
                )
                val fullResponse = StringBuilder()
                chatClient.streamChat(request).collect { chunk ->
                    fullResponse.append(chunk)
                    _streamingText.update { it + chunk }
                }
                // 流式结束，将完整响应转为消息
                val assistantMessage = ChatMessage(
                    id = UUID.randomUUID().toString(),
                    conversationId = conversationId,
                    role = "assistant",
                    content = fullResponse.toString(),
                    createdAt = System.currentTimeMillis()
                )
                _messages.update { it + assistantMessage }
                _streamingText.value = ""
            } catch (e: Exception) {
                _errorMessage.value = "发送失败：${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * 删除指定消息：先调用 BFF API，成功后从本地列表移除。
     *
     * @param messageId 消息 ID
     */
    fun deleteMessage(messageId: String) {
        viewModelScope.launch {
            try {
                messageRepo.delete(messageId)
                _messages.update { msgs -> msgs.filterNot { it.id == messageId } }
            } catch (e: Exception) {
                _errorMessage.value = "删除消息失败：${e.message}"
            }
        }
    }

    /**
     * 重发用户消息：移除该消息及其后续所有消息，再以该消息内容重新发起流式请求。
     *
     * 仅对 role == "user" 的消息生效；非用户消息直接返回。
     *
     * @param message 需要重发的用户消息
     */
    fun resendMessage(message: ChatMessage) {
        if (message.role != "user") return
        val conversationId = currentConversationId ?: return
        // 找到该消息在列表中的位置，移除它及之后的所有消息
        val current = _messages.value
        val index = current.indexOfFirst { it.id == message.id }
        if (index < 0) return
        val kept = current.subList(0, index).toList()
        // 重新构造一条同内容的用户消息（保持原 ID 以便 UI 复用 key）
        val newUserMessage = message.copy(
            createdAt = System.currentTimeMillis()
        )
        _messages.value = kept + newUserMessage
        streamSend(newUserMessage)
    }

    fun clearError() {
        _errorMessage.value = null
    }
}
