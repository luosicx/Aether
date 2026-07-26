package com.aether.ui.rag

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aether.data.api.AetherApi
import com.aether.data.model.DocumentChunk
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * 知识库搜索 ViewModel。
 *
 * 通过 [AetherApi.searchDocuments] 调用 BFF 的 `/rag/search` 端点，
 * 返回与查询相关的文档分块。
 */
class KnowledgeBaseViewModel(private val api: AetherApi) : ViewModel() {

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _searchResults = MutableStateFlow<List<DocumentChunk>>(emptyList())
    val searchResults: StateFlow<List<DocumentChunk>> = _searchResults.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    /**
     * 更新搜索框输入文本（不触发请求）。
     */
    fun updateQuery(query: String) {
        _searchQuery.value = query
    }

    /**
     * 执行知识库搜索。空字符串直接清空结果。
     *
     * @param query 搜索关键词；若为空则清空结果
     */
    fun search(query: String) {
        val trimmed = query.trim()
        _searchQuery.value = query
        if (trimmed.isEmpty()) {
            _searchResults.value = emptyList()
            _errorMessage.value = null
            return
        }
        _isLoading.value = true
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                val results = api.searchDocuments(trimmed, limit = 3)
                _searchResults.value = results
            } catch (e: Exception) {
                _errorMessage.value = "搜索失败：${e.message}"
                _searchResults.value = emptyList()
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * 清空错误状态。
     */
    fun clearError() {
        _errorMessage.value = null
    }

    /**
     * 重置全部状态（返回初始空状态）。
     */
    fun reset() {
        _searchQuery.value = ""
        _searchResults.value = emptyList()
        _errorMessage.value = null
        _isLoading.value = false
    }
}
