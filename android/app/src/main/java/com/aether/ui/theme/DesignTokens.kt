package com.aether.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Aether 设计令牌（Compose 友好类型）。
 * 单一真相源：DesignTokens/tokens.json
 * 从原 com.aether.design.DesignTokens 迁移而来，修复了 Color.argb 非法调用，
 * 改用十六进制 Color 字面量与拆分的 object 分组。
 */

object AetherColors {
    val deepSpace: Color = Color(0xFF0A0E1A)        // 深空黑/浅空白基底
    val aetherPurple: Color = Color(0xFF7C3AED)     // 神秘紫强调色
    val electricBlue: Color = Color(0xFF00D4FF)     // 电光蓝交互色
    val liquidGlass: Color = Color(0x801C1C2E)      // 液态玻璃卡片基底（带 alpha）
    val nebulaGlow: Color = Color(0xFFFFE5B4)       // 星云光晕高光
    val starlight: Color = Color(0xFFE5E7EB)        // 星光白/夜色文字
    val duskGray: Color = Color(0xFF4B5563)         // 暮色灰（系统色 fallback）
}

object AetherTypography {
    val title: TextUnit = 28.sp            // Aether 标题
    val titleWeight: FontWeight = FontWeight.SemiBold
    val display: TextUnit = 48.sp          // Aether 展示字体（开屏 Logo / 大标题）
    val displayWeight: FontWeight = FontWeight.Bold
    val body: TextUnit = 16.sp             // Aether 正文
    val bodyWeight: FontWeight = FontWeight.Normal
}

object AetherSpacing {
    val xs: Dp = 2.dp
    val sm: Dp = 4.dp
    val md: Dp = 8.dp
    val lg: Dp = 12.dp
    val xl: Dp = 16.dp
    val xxl: Dp = 24.dp
    val xxxl: Dp = 32.dp
}

object AetherCornerRadius {
    val small: Dp = 12.dp
    val medium: Dp = 16.dp
    val large: Dp = 24.dp
    val pill: Dp = 999.dp
}

object AetherAnimation {
    const val transitionMs: Int = 250      // 页面转场 0.25s
    const val messageAppearMs: Int = 200   // 消息进入 0.2s
    const val buttonPressMs: Int = 100     // 按钮按下 0.1s
}
