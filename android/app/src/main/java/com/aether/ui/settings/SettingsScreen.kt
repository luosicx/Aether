package com.aether.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aether.data.api.BffConfigStore
import com.aether.ui.theme.AetherColors
import com.aether.ui.theme.AetherCornerRadius
import com.aether.ui.theme.AetherSpacing
import kotlinx.coroutines.launch

/**
 * 设置页：BFF 端点、Token、默认模型、主题色。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    store: BffConfigStore,
    onBack: () -> Unit
) {
    val scope = rememberCoroutineScope()

    val config by store.config.collectAsStateWithLifecycle(initialValue = null)
    val defaultModel by store.defaultModel.collectAsStateWithLifecycle(initialValue = "deepseek-chat")
    val accent by store.accentColor.collectAsStateWithLifecycle(initialValue = "purple")

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
    val accents = listOf("purple" to "神秘紫", "blue" to "电光蓝", "glow" to "星云光")

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(AetherSpacing.lg.dp),
            verticalArrangement = Arrangement.spacedBy(AetherSpacing.lg.dp)
        ) {
            // BFF 端点
            SectionTitle("BFF 网关")
            OutlinedTextField(
                value = baseUrl,
                onValueChange = { baseUrl = it },
                label = { Text("BFF 端点 URL") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AetherCornerRadius.medium.dp)
            )
            OutlinedTextField(
                value = userToken,
                onValueChange = { userToken = it },
                label = { Text("X-BFF-Token") },
                singleLine = true,
                visualTransformation = if (tokenVisible) VisualTransformation.None
                    else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    TextButton(onClick = { tokenVisible = !tokenVisible }) {
                        Text(if (tokenVisible) "隐藏" else "显示")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AetherCornerRadius.medium.dp)
            )

            HorizontalDivider()

            // 默认模型
            SectionTitle("默认模型")
            ModelSelector(selected = defaultModel, options = models) { selected ->
                scope.launch { store.setDefaultModel(selected) }
            }

            HorizontalDivider()

            // 主题色
            SectionTitle("主题色")
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
                shape = RoundedCornerShape(AetherCornerRadius.large.dp)
            ) {
                Text("保存")
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModelSelector(
    selected: String,
    options: List<String>,
    onSelected: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded }
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text("模型") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
            shape = RoundedCornerShape(AetherCornerRadius.medium.dp)
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
