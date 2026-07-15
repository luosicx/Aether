package com.aether.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aether.data.model.ChatMessage
import com.aether.ui.theme.AetherColors
import com.aether.ui.theme.AetherCornerRadius
import com.aether.ui.theme.AetherSpacing

/**
 * 聊天界面：消息列表 + 流式打字光标 + 输入栏 + 顶部栏。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    conversationId: String,
    conversationTitle: String,
    viewModel: ChatViewModel,
    onBack: () -> Unit,
    onOpenSettings: () -> Unit
) {
    LaunchedEffect(conversationId) {
        viewModel.loadMessages(conversationId)
    }

    val messages by viewModel.messages.collectAsStateWithLifecycle()
    val streamingText by viewModel.streamingText.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val errorMessage by viewModel.errorMessage.collectAsStateWithLifecycle()

    var input by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    // 新消息到达时滚动到底部
    LaunchedEffect(messages.size, streamingText) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(conversationTitle, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "设置")
                    }
                }
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

            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = AetherSpacing.md),
                verticalArrangement = Arrangement.spacedBy(AetherSpacing.md),
                contentPadding = PaddingValues(vertical = AetherSpacing.md)
            ) {
                items(messages, key = { it.id }) { message ->
                    MessageBubble(message)
                }
                if (isLoading && streamingText.isEmpty()) {
                    item { TypingIndicator() }
                }
                if (streamingText.isNotEmpty()) {
                    item {
                        StreamingBubble(streamingText)
                    }
                }
            }

            ChatInputBar(
                text = input,
                onTextChange = { input = it },
                enabled = !isLoading,
                onSend = {
                    if (input.isNotBlank()) {
                        viewModel.send(input)
                        input = ""
                    }
                }
            )
        }
    }
}

@Composable
private fun MessageBubble(message: ChatMessage) {
    val isUser = message.role == "user"
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Surface(
            color = if (isUser) AetherColors.aetherPurple else AetherColors.liquidGlass,
            shape = RoundedCornerShape(AetherCornerRadius.medium),
            modifier = Modifier.widthIn(max = 320.dp)
        ) {
            Text(
                text = message.content,
                modifier = Modifier.padding(horizontal = AetherSpacing.lg, vertical = AetherSpacing.md),
                color = if (isUser) AetherColors.starlight else AetherColors.starlight,
                style = MaterialTheme.typography.bodyLarge
            )
        }
    }
}

@Composable
private fun StreamingBubble(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start
    ) {
        Surface(
            color = AetherColors.liquidGlass,
            shape = RoundedCornerShape(AetherCornerRadius.medium),
            modifier = Modifier.widthIn(max = 320.dp)
        ) {
            Text(
                text = buildString { append(text); append("▌") },
                modifier = Modifier.padding(horizontal = AetherSpacing.lg, vertical = AetherSpacing.md),
                color = AetherColors.starlight,
                style = MaterialTheme.typography.bodyLarge
            )
        }
    }
}

@Composable
private fun TypingIndicator() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start
    ) {
        Surface(
            color = AetherColors.liquidGlass,
            shape = RoundedCornerShape(AetherCornerRadius.medium)
        ) {
            Text(
                text = "思考中…",
                modifier = Modifier.padding(horizontal = AetherSpacing.lg, vertical = AetherSpacing.md),
                color = AetherColors.starlight,
                fontWeight = FontWeight.Light
            )
        }
    }
}

@Composable
private fun ErrorBanner(message: String, onClose: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(AetherCornerRadius.small),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AetherSpacing.md, vertical = AetherSpacing.sm)
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
            TextButton(onClick = onClose) { Text("关闭") }
        }
    }
}

@Composable
private fun ChatInputBar(
    text: String,
    onTextChange: (String) -> Unit,
    enabled: Boolean,
    onSend: () -> Unit
) {
    Surface(
        tonalElevation = 4.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AetherSpacing.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = text,
                onValueChange = onTextChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("输入消息…") },
                maxLines = 5,
                shape = RoundedCornerShape(AetherCornerRadius.large)
            )
            Spacer(modifier = Modifier.width(AetherSpacing.sm))
            FilledIconButton(
                onClick = onSend,
                enabled = enabled && text.isNotBlank(),
                modifier = Modifier.clip(RoundedCornerShape(AetherCornerRadius.large))
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "发送")
            }
        }
    }
}
