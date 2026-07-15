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
        _isLoading.value = true
        _streamingText.value = ""
        _errorMessage.value = null

        viewModelScope.launch {
            try {
                val request = ChatRequest(
                    message = trimmed,
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

    fun clearError() {
        _errorMessage.value = null
    }
}
