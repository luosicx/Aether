package com.aether.ui.rag

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aether.app.R
import com.aether.data.model.DocumentChunk
import com.aether.ui.theme.AetherColors
import com.aether.ui.theme.AetherCornerRadius
import com.aether.ui.theme.AetherSpacing

/**
 * 知识库搜索界面：搜索栏 + 结果列表 + 空/加载/错误状态。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KnowledgeBaseScreen(
    viewModel: KnowledgeBaseViewModel,
    onBack: () -> Unit
) {
    val query by viewModel.searchQuery.collectAsStateWithLifecycle()
    val results by viewModel.searchResults.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val errorMessage by viewModel.errorMessage.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.knowledge_base_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.settings_back)
                        )
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = AetherSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(AetherSpacing.lg)
        ) {
            // 搜索栏
            SearchBar(
                text = query,
                onTextChange = viewModel::updateQuery,
                isLoading = isLoading,
                onSearch = { viewModel.search(query) }
            )

            // 错误 Banner
            errorMessage?.let { msg ->
                ErrorBanner(msg, onClose = viewModel::clearError, onRetry = { viewModel.search(query) })
            }

            // 加载状态
            if (isLoading) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = AetherSpacing.xxl),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else if (results.isEmpty() && query.isBlank()) {
                // 空状态：未搜索
                EmptyState(stringResource(R.string.knowledge_base_empty))
            } else if (results.isEmpty()) {
                // 已搜索但无结果
                EmptyState(stringResource(R.string.knowledge_base_no_results))
            } else {
                // 结果列表
                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(AetherSpacing.md),
                    contentPadding = PaddingValues(vertical = AetherSpacing.sm)
                ) {
                    items(results, key = { it.id }) { chunk ->
                        DocumentChunkCard(chunk)
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchBar(
    text: String,
    onTextChange: (String) -> Unit,
    isLoading: Boolean,
    onSearch: () -> Unit
) {
    val searchLabel = stringResource(R.string.knowledge_base_search)
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        OutlinedTextField(
            value = text,
            onValueChange = onTextChange,
            modifier = Modifier.weight(1f),
            placeholder = { Text(stringResource(R.string.knowledge_base_search_placeholder)) },
            singleLine = true,
            shape = RoundedCornerShape(AetherCornerRadius.medium)
        )
        Spacer(modifier = Modifier.width(AetherSpacing.sm))
        FilledIconButton(
            onClick = onSearch,
            enabled = !isLoading && text.isNotBlank(),
            modifier = Modifier.clip(RoundedCornerShape(AetherCornerRadius.medium))
        ) {
            Icon(Icons.Default.Search, contentDescription = searchLabel)
        }
    }
}

@Composable
private fun DocumentChunkCard(chunk: DocumentChunk) {
    val unnamedLabel = stringResource(R.string.knowledge_base_unnamed)
    val sourceLabel = stringResource(R.string.knowledge_base_source, chunk.source)
    val relevanceLabel = stringResource(R.string.knowledge_base_relevance, chunk.weight)
    Surface(
        color = AetherColors.liquidGlass,
        shape = RoundedCornerShape(AetherCornerRadius.medium),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(AetherSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(AetherSpacing.sm)
        ) {
            // 来源标题
            Text(
                text = chunk.source.ifBlank { unnamedLabel },
                style = MaterialTheme.typography.titleMedium,
                color = AetherColors.nebulaGlow,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            // 内容片段
            Text(
                text = chunk.content,
                style = MaterialTheme.typography.bodyMedium,
                color = AetherColors.starlight,
                maxLines = 6,
                overflow = TextOverflow.Ellipsis
            )
            // 来源 + 权重（相关度分数）
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = sourceLabel,
                    style = MaterialTheme.typography.labelSmall,
                    color = AetherColors.duskGray,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                Text(
                    text = relevanceLabel,
                    style = MaterialTheme.typography.labelSmall,
                    color = AetherColors.electricBlue
                )
            }
        }
    }
}

@Composable
private fun EmptyState(message: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = AetherSpacing.xxxl),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            color = AetherColors.duskGray
        )
    }
}

@Composable
private fun ErrorBanner(
    message: String,
    onClose: () -> Unit,
    onRetry: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(AetherCornerRadius.small),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AetherSpacing.lg, vertical = AetherSpacing.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = message,
                modifier = Modifier.weight(1f),
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            TextButton(onClick = onRetry) { Text(stringResource(R.string.knowledge_base_retry)) }
            TextButton(onClick = onClose) { Text(stringResource(R.string.knowledge_base_close)) }
        }
    }
}
