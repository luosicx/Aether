package com.aether.ui.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aether.app.R
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
    onOpenSettings: () -> Unit,
    onOpenKnowledgeBase: () -> Unit = {}
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
    val context = LocalContext.current

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
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.chat_back)
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onOpenKnowledgeBase) {
                        Icon(
                            Icons.Default.LibraryBooks,
                            contentDescription = stringResource(R.string.chat_knowledge_base)
                        )
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(
                            Icons.Default.Settings,
                            contentDescription = stringResource(R.string.chat_settings)
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
                    MessageBubble(
                        message = message,
                        onCopy = { text -> copyText(context, text) },
                        onResend = viewModel::resendMessage,
                        onDelete = viewModel::deleteMessage
                    )
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

/**
 * 复制文本到系统剪贴板。
 */
private fun copyText(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("AetherMessage", text))
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    message: ChatMessage,
    onCopy: (String) -> Unit,
    onResend: (ChatMessage) -> Unit,
    onDelete: (String) -> Unit
) {
    val isUser = message.role == "user"
    var menuExpanded by remember { mutableStateOf(false) }
    val copyLabel = stringResource(R.string.chat_copy)
    val retryLabel = stringResource(R.string.chat_retry)
    val deleteLabel = stringResource(R.string.chat_delete)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Surface(
            color = if (isUser) AetherColors.aetherPurple else AetherColors.liquidGlass,
            shape = RoundedCornerShape(AetherCornerRadius.medium),
            modifier = Modifier
                .widthIn(max = 320.dp)
                .combinedClickable(
                    onClick = {},
                    onLongClick = { menuExpanded = true }
                )
        ) {
            Box {
                if (isUser) {
                    // 用户消息保持纯文本
                    Text(
                        text = message.content,
                        modifier = Modifier.padding(horizontal = AetherSpacing.lg, vertical = AetherSpacing.md),
                        color = AetherColors.starlight,
                        style = MaterialTheme.typography.bodyLarge
                    )
                } else {
                    // AI 消息使用 Markdown 渲染（流式结束后切换）
                    MarkdownText(
                        markdown = message.content,
                        modifier = Modifier.padding(horizontal = AetherSpacing.lg, vertical = AetherSpacing.md),
                        style = MaterialTheme.typography.bodyLarge
                    )
                }
                DropdownMenu(
                    expanded = menuExpanded,
                    onDismissRequest = { menuExpanded = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(copyLabel) },
                        leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) },
                        onClick = {
                            onCopy(message.content)
                            menuExpanded = false
                        }
                    )
                    if (isUser) {
                        DropdownMenuItem(
                            text = { Text(retryLabel) },
                            leadingIcon = { Icon(Icons.Default.Refresh, contentDescription = null) },
                            onClick = {
                                onResend(message)
                                menuExpanded = false
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = { Text(deleteLabel) },
                        leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null) },
                        onClick = {
                            onDelete(message.id)
                            menuExpanded = false
                        }
                    )
                }
            }
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
                text = stringResource(R.string.chat_thinking),
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
            TextButton(onClick = onClose) { Text(stringResource(R.string.chat_close)) }
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
                placeholder = { Text(stringResource(R.string.chat_input_placeholder)) },
                maxLines = 5,
                shape = RoundedCornerShape(AetherCornerRadius.large)
            )
            Spacer(modifier = Modifier.width(AetherSpacing.sm))
            FilledIconButton(
                onClick = onSend,
                enabled = enabled && text.isNotBlank(),
                modifier = Modifier.clip(RoundedCornerShape(AetherCornerRadius.large))
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    contentDescription = stringResource(R.string.chat_send)
                )
            }
        }
    }
}
