package com.aether.ui.conversation

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aether.data.model.Conversation
import com.aether.ui.theme.AetherColors
import com.aether.ui.theme.AetherCornerRadius
import com.aether.ui.theme.AetherSpacing
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 会话列表：展示所有会话，支持置顶、删除与新建。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationListScreen(
    viewModel: ConversationListViewModel,
    onOpenConversation: (Conversation) -> Unit,
    onOpenSettings: () -> Unit
) {
    val conversations by viewModel.conversations.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val errorMessage by viewModel.errorMessage.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("以太", fontWeight = FontWeight.SemiBold) },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "设置")
                    }
                }
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { viewModel.createConversation(onCreated = onOpenConversation) },
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
                text = { Text("新会话") }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            errorMessage?.let { msg ->
                ErrorBanner(msg, onClose = viewModel::clearError)
            }

            if (isLoading && conversations.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else if (conversations.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text("暂无会话，点击右下角开始对话", color = AetherColors.starlight)
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(AetherSpacing.md.dp),
                    verticalArrangement = Arrangement.spacedBy(AetherSpacing.sm.dp)
                ) {
                    items(conversations, key = { it.id }) { conv ->
                        ConversationRow(
                            conversation = conv,
                            onClick = { onOpenConversation(conv) },
                            onTogglePin = { viewModel.togglePin(conv) },
                            onDelete = { viewModel.delete(conv.id) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ConversationRow(
    conversation: Conversation,
    onClick: () -> Unit,
    onTogglePin: () -> Unit,
    onDelete: () -> Unit
) {
    val timeText = remember(conversation.updatedAt) {
        SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(conversation.updatedAt))
    }
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(AetherCornerRadius.medium.dp),
        colors = CardDefaults.cardColors(containerColor = AetherColors.liquidGlass)
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = AetherSpacing.lg.dp, vertical = AetherSpacing.md.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (conversation.isPinned) {
                        Icon(
                            Icons.Filled.PushPin,
                            contentDescription = "已置顶",
                            tint = AetherColors.nebulaGlow,
                            modifier = Modifier
                                .size(16.dp)
                                .padding(end = AetherSpacing.xs.dp)
                        )
                    }
                    Text(
                        text = conversation.title,
                        style = MaterialTheme.typography.titleMedium,
                        color = AetherColors.starlight,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(modifier = Modifier.height(AetherSpacing.xs.dp))
                Text(
                    text = conversation.lastMessagePreview.ifEmpty { "点击开始对话" },
                    style = MaterialTheme.typography.bodyMedium,
                    color = AetherColors.starlight.copy(alpha = 0.7f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(AetherSpacing.xs.dp))
                Text(
                    text = timeText,
                    style = MaterialTheme.typography.labelSmall,
                    color = AetherColors.starlight.copy(alpha = 0.5f)
                )
            }
            IconButton(onClick = onTogglePin) {
                Icon(
                    if (conversation.isPinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                    contentDescription = "置顶"
                )
            }
            IconButton(onClick = onDelete) {
                Text("删除", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun ErrorBanner(message: String, onClose: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(AetherCornerRadius.small.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AetherSpacing.md.dp, vertical = AetherSpacing.sm.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AetherSpacing.lg.dp, vertical = AetherSpacing.sm.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = message,
                modifier = Modifier.weight(1f),
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            TextButton(onClick = onClose) { Text("关闭") }
        }
    }
}
