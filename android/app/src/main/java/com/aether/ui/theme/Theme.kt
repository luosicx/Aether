package com.aether.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight

/**
 * Aether 深色主题：基于 Material 3 darkColorScheme，
 * 颜色与字号取自 DesignTokens。
 */
@Composable
fun AetherTheme(content: @Composable () -> Unit) {
    val colorScheme = darkColorScheme(
        primary = AetherColors.aetherPurple,
        secondary = AetherColors.electricBlue,
        background = AetherColors.deepSpace,
        surface = AetherColors.liquidGlass,
        onPrimary = AetherColors.starlight,
        onSecondary = AetherColors.deepSpace,
        onBackground = AetherColors.starlight,
        onSurface = AetherColors.starlight,
        tertiary = AetherColors.nebulaGlow
    )
    MaterialTheme(
        colorScheme = colorScheme,
        typography = androidx.compose.material3.Typography(
            titleLarge = TextStyle(
                fontSize = AetherTypography.title,
                fontWeight = FontWeight.SemiBold
            ),
            displayLarge = TextStyle(
                fontSize = AetherTypography.display,
                fontWeight = FontWeight.Bold
            ),
            bodyLarge = TextStyle(
                fontSize = AetherTypography.body,
                fontWeight = FontWeight.Normal
            )
        ),
        content = content
    )
}
