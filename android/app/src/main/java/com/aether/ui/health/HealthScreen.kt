package com.aether.ui.health

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aether.app.R
import com.aether.ui.theme.AetherColors
import com.aether.ui.theme.AetherCornerRadius
import com.aether.ui.theme.AetherSpacing

/**
 * 健康洞察界面：日期选择 + 数据卡片 + 上传按钮。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HealthScreen(
    viewModel: HealthViewModel,
    onBack: () -> Unit
) {
    val selectedDate by viewModel.selectedDate.collectAsStateWithLifecycle()
    val summary by viewModel.healthSummary.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val errorMessage by viewModel.errorMessage.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.health_title)) },
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
            // 日期选择
            OutlinedTextField(
                value = selectedDate,
                onValueChange = { viewModel.selectDate(it) },
                label = { Text(stringResource(R.string.health_date_label)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AetherCornerRadius.medium)
            )

            // 错误 Banner
            errorMessage?.let { msg ->
                ErrorBanner(msg, onClose = viewModel::clearError)
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
            } else {
                // 健康数据卡片
                MetricCard(
                    title = stringResource(R.string.health_steps),
                    value = summary?.steps?.toString() ?: "—",
                    unit = stringResource(R.string.health_steps_unit),
                    icon = Icons.Default.DirectionsWalk
                )
                MetricCard(
                    title = stringResource(R.string.health_sleep_hours),
                    value = summary?.sleepHours?.let { "%.1f".format(it) } ?: "—",
                    unit = stringResource(R.string.health_hours),
                    icon = Icons.Default.Bedtime
                )
                MetricCard(
                    title = stringResource(R.string.health_resting_heart_rate),
                    value = summary?.restingHeartRate?.toString() ?: "—",
                    unit = stringResource(R.string.health_bpm),
                    icon = Icons.Default.Favorite
                )

                Spacer(modifier = Modifier.weight(1f))

                // 上传今日健康数据
                Button(
                    onClick = viewModel::uploadCurrentSummary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(AetherCornerRadius.large)
                ) {
                    Icon(Icons.Default.Upload, contentDescription = null)
                    Spacer(modifier = Modifier.width(AetherSpacing.sm))
                    Text(stringResource(R.string.health_upload))
                }
            }
        }
    }
}

@Composable
private fun MetricCard(
    title: String,
    value: String,
    unit: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector
) {
    Surface(
        color = AetherColors.liquidGlass,
        shape = RoundedCornerShape(AetherCornerRadius.medium),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .padding(AetherSpacing.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AetherSpacing.lg)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = AetherColors.electricBlue
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(AetherSpacing.xs)
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.labelMedium,
                    color = AetherColors.duskGray
                )
                Row(
                    verticalAlignment = Alignment.Bottom
                ) {
                    Text(
                        text = value,
                        style = MaterialTheme.typography.displayLarge,
                        color = AetherColors.starlight,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.width(AetherSpacing.sm))
                    Text(
                        text = unit,
                        style = MaterialTheme.typography.bodyLarge,
                        color = AetherColors.nebulaGlow,
                        modifier = Modifier.padding(bottom = 8.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun ErrorBanner(message: String, onClose: () -> Unit) {
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
            TextButton(onClick = onClose) { Text(stringResource(R.string.health_close)) }
        }
    }
}
