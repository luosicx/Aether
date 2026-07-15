package com.aether.ui.conversation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aether.data.model.Conversation
import com.aether.data.repository.ConversationRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class ConversationListViewModel(
    private val repository: ConversationRepository
) : ViewModel() {

    private val _conversations = MutableStateFlow<List<Conversation>>(emptyList())
    val conversations: StateFlow<List<Conversation>> = _conversations.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                _conversations.value = repository.fetchAll()
            } catch (e: Exception) {
                _errorMessage.value = "加载会话失败：${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun createConversation(onCreated: (Conversation) -> Unit) {
        viewModelScope.launch {
            try {
                val title = "新会话 ${(_conversations.value.size + 1)}"
                val conv = repository.create(title)
                _conversations.update { listOf(conv) + it }
                onCreated(conv)
            } catch (e: Exception) {
                _errorMessage.value = "创建会话失败：${e.message}"
            }
        }
    }

    fun togglePin(conversation: Conversation) {
        viewModelScope.launch {
            try {
                val updated = repository.update(conversation.id, isPinned = !conversation.isPinned)
                _conversations.value = _conversations.value.map {
                    if (it.id == updated.id) updated else it
                }
            } catch (e: Exception) {
                _errorMessage.value = "更新失败：${e.message}"
            }
        }
    }

    fun delete(id: String) {
        viewModelScope.launch {
            try {
                repository.delete(id)
                _conversations.value = _conversations.value.filterNot { it.id == id }
            } catch (e: Exception) {
                _errorMessage.value = "删除失败：${e.message}"
            }
        }
    }

    fun clearError() {
        _errorMessage.value = null
    }
}
