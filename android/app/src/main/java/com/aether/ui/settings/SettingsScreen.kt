package com.aether.ui.settings

import android.app.Activity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aether.app.R
import com.aether.data.api.BffConfigStore
import com.aether.ui.theme.AetherColors
import com.aether.ui.theme.AetherCornerRadius
import com.aether.ui.theme.AetherSpacing
import kotlinx.coroutines.launch

/**
 * 设置页：BFF 端点、Token、默认模型、主题色、语言、知识库 / 健康洞察入口。
 *
 * 语言切换会写入 DataStore 并立即调用 [Activity.recreate] 让 res/values-* 生效。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    store: BffConfigStore,
    onBack: () -> Unit,
    onOpenKnowledgeBase: () -> Unit = {},
    onOpenHealth: () -> Unit = {}
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    val config by store.config.collectAsStateWithLifecycle(initialValue = null)
    val defaultModel by store.defaultModel.collectAsStateWithLifecycle(initialValue = "deepseek-chat")
    val accent by store.accentColor.collectAsStateWithLifecycle(initialValue = "purple")
    val language by store.language.collectAsStateWithLifecycle(initialValue = BffConfigStore.DEFAULT_LANGUAGE)

    var baseUrl by remember { mutableStateOf("") }
    var userToken by remember { mutableStateOf("") }
    var tokenVisible by remember { mutableStateOf(false) }

    // 当持久化配置加载后同步到本地输入状态
    LaunchedEffect(config) {
        config?.let {
            baseUrl = it.baseUrl
            userToken = it.userToken
        }
    }

    val models = listOf("deepseek-chat", "deepseek-reasoner", "qwen-plus", "qwen-turbo")
    val accents = listOf(
        "purple" to stringResource(R.string.settings_accent_color_purple),
        "blue" to stringResource(R.string.settings_accent_color_blue),
        "glow" to stringResource(R.string.settings_accent_color_glow)
    )
    // 语言列表：代码 -> 显示名（显示名用各自语言）
    val languages = listOf(
        "zh-Hans" to stringResource(R.string.language_zh_hans),
        "zh-Hant" to stringResource(R.string.language_zh_hant),
        "en" to stringResource(R.string.language_en),
        "ja" to stringResource(R.string.language_ja),
        "ko" to stringResource(R.string.language_ko),
        "fr" to stringResource(R.string.language_fr),
        "de" to stringResource(R.string.language_de),
        "es" to stringResource(R.string.language_es)
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
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
                .padding(AetherSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(AetherSpacing.lg)
        ) {
            // BFF 端点
            SectionTitle(stringResource(R.string.settings_bff_gateway))
            OutlinedTextField(
                value = baseUrl,
                onValueChange = { baseUrl = it },
                label = { Text(stringResource(R.string.settings_bff_url)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AetherCornerRadius.medium)
            )
            OutlinedTextField(
                value = userToken,
                onValueChange = { userToken = it },
                label = { Text(stringResource(R.string.settings_bff_token)) },
                singleLine = true,
                visualTransformation = if (tokenVisible) VisualTransformation.None
                    else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    TextButton(onClick = { tokenVisible = !tokenVisible }) {
                        Text(
                            if (tokenVisible) stringResource(R.string.settings_hide_token)
                            else stringResource(R.string.settings_show_token)
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AetherCornerRadius.medium)
            )

            HorizontalDivider()

            // 默认模型
            SectionTitle(stringResource(R.string.settings_default_model))
            ModelSelector(selected = defaultModel, options = models) { selected ->
                scope.launch { store.setDefaultModel(selected) }
            }

            HorizontalDivider()

            // 主题色
            SectionTitle(stringResource(R.string.settings_accent_color))
            accents.forEach { (key, label) ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    RadioButton(selected = accent == key, onClick = {
                        scope.launch { store.setAccentColor(key) }
                    })
                    Text(label, color = AetherColors.starlight)
                }
            }

            HorizontalDivider()

            // 语言选择器
            SectionTitle(stringResource(R.string.settings_language))
            languages.forEach { (code, label) ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    RadioButton(
                        selected = language == code,
                        onClick = {
                            scope.launch {
                                store.setLanguage(code)
                                // 重启 Activity 让 res/values-* 资源生效
                                (context as? Activity)?.recreate()
                            }
                        }
                    )
                    Text(label, color = AetherColors.starlight)
                }
            }

            HorizontalDivider()

            // 功能入口
            SectionTitle(stringResource(R.string.settings_features))
            EntryRow(
                title = stringResource(R.string.settings_knowledge_base),
                subtitle = stringResource(R.string.settings_knowledge_base_subtitle),
                icon = Icons.Default.LibraryBooks,
                onClick = onOpenKnowledgeBase
            )
            EntryRow(
                title = stringResource(R.string.settings_health),
                subtitle = stringResource(R.string.settings_health_subtitle),
                icon = Icons.Default.Favorite,
                onClick = onOpenHealth
            )

            Spacer(modifier = Modifier.weight(1f))

            // 保存按钮
            Button(
                onClick = {
                    scope.launch {
                        store.setBaseUrl(baseUrl.trim())
                        store.setUserToken(userToken.trim())
                        onBack()
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(AetherCornerRadius.large)
            ) {
                Text(stringResource(R.string.settings_save))
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = AetherColors.nebulaGlow
    )
}

/**
 * 设置页功能入口行：左图标 + 标题/副标题，右箭头。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EntryRow(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        color = AetherColors.liquidGlass,
        shape = RoundedCornerShape(AetherCornerRadius.medium),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AetherSpacing.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AetherSpacing.lg)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = AetherColors.electricBlue
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = AetherColors.starlight
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = AetherColors.duskGray
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = AetherColors.duskGray
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModelSelector(
    selected: String,
    options: List<String>,
    onSelected: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val modelLabel = stringResource(R.string.settings_model)
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded }
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text(modelLabel) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
            shape = RoundedCornerShape(AetherCornerRadius.medium)
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelected(option)
                        expanded = false
                    }
                )
            }
        }
    }
}
