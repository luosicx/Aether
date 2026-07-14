package com.aether.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Auto-generated from tokens.json. Do not edit manually.
 * 单一真相源：DesignTokens/tokens.json
 * 生成脚本：scripts/gen_kotlin_tokens.py
 */
object DesignTokens {

    // MARK: - Color
    val deepSpace: Color = Color.argb(255, 10, 14, 26) // 深空黑/浅空白基底
    val aetherPurple: Color = Color.argb(255, 124, 58, 237) // 神秘紫强调色
    val electricBlue: Color = Color.argb(255, 0, 212, 255) // 电光蓝交互色
    val liquidGlass: Color = Color.argb(128, 28, 28, 46) // 液态玻璃卡片基底（带 alpha）
    val nebulaGlow: Color = Color.argb(255, 255, 229, 180) // 星云光晕高光
    val starlight: Color = Color.argb(255, 229, 231, 235) // 星光白/夜色文字
    val duskGray: Color = Color.argb(255, 75, 85, 99) // 暮色灰（系统色 fallback）

    // MARK: - Typography
    val aetherTitleSize: androidx.compose.ui.unit.TextUnit = 28.sp // Aether 标题
    val aetherTitleWeight: FontWeight = FontWeight.SemiBold
    val aetherDisplaySize: androidx.compose.ui.unit.TextUnit = 48.sp // Aether 展示字体（开屏 Logo / 大标题）
    val aetherDisplayWeight: FontWeight = FontWeight.Bold
    val aetherBodySize: androidx.compose.ui.unit.TextUnit = 16.sp // Aether 正文
    val aetherBodyWeight: FontWeight = FontWeight.Normal

    // MARK: - Spacing
    val spacingXS: androidx.compose.ui.unit.Dp = 2.dp // 2pt
    val spacingSM: androidx.compose.ui.unit.Dp = 4.dp // 4pt
    val spacingMD: androidx.compose.ui.unit.Dp = 8.dp // 8pt
    val spacingLG: androidx.compose.ui.unit.Dp = 12.dp // 12pt
    val spacingXL: androidx.compose.ui.unit.Dp = 16.dp // 16pt
    val spacingXXL: androidx.compose.ui.unit.Dp = 24.dp // 24pt
    val spacingXXXL: androidx.compose.ui.unit.Dp = 32.dp // 32pt

    // MARK: - CornerRadius
    val cornerSmall: androidx.compose.ui.unit.Dp = 12.dp // 小圆角
    val cornerMedium: androidx.compose.ui.unit.Dp = 16.dp // 中圆角
    val cornerLarge: androidx.compose.ui.unit.Dp = 24.dp // 大圆角
    val cornerPill: androidx.compose.ui.unit.Dp = 999.dp // 胶囊圆角

    // MARK: - Animation (duration in ms)
    val animTransitionMs: Int = 250 // 页面转场 0.25s
    val animMessageAppearMs: Int = 200 // 消息进入 0.2s
    val animButtonPressMs: Int = 100 // 按钮按下 0.1s

}
