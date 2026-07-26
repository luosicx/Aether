package com.aether.ui.chat

import android.graphics.Color
import android.text.method.LinkMovementMethod
import android.widget.TextView
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.viewinterop.AndroidView
import com.aether.ui.theme.AetherColors
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.Markwon
import io.noties.markwon.core.CorePlugin
import io.noties.markwon.core.MarkwonTheme
import io.noties.markwon.ext.strikethrough.StrikethroughPlugin
import io.noties.markwon.ext.tables.TablePlugin
import io.noties.markwon.ext.tasklist.TaskListPlugin
import io.noties.markwon.linkify.LinkifyPlugin
import io.noties.markwon.syntax.Prism4jThemeDarkula
import io.noties.markwon.syntax.SyntaxHighlightPlugin
import io.noties.prism4j.GrammarLocator
import io.noties.prism4j.Prism4j

/**
 * Markdown 渲染 Compose 组件：包装 Markwon 为可复用的 Composable。
 *
 * 支持特性：
 * - 标题（h1-h6）
 * - 加粗 / 斜体 / 删除线
 * - 代码块（语法高亮主题 Prism4jThemeDarkula，代码块背景 LiquidGlass）
 * - 表格（TablePlugin）
 * - 任务列表（TaskListPlugin）
 * - 链接（Linkify，颜色 ElectricBlue）
 *
 * 实现方式：`AndroidView` + `TextView` 渲染，Markwon 实例在 Composable 作用域内 remember。
 *
 * @param markdown 原始 Markdown 文本
 * @param modifier Compose 修饰符
 * @param style 文字样式（fontSize / fontWeight 等会同步到 TextView）
 */
@Composable
fun MarkdownText(
    markdown: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyMedium
) {
    val context = LocalContext.current

    // 构建 Markwon 实例（每个 Composable 作用域单例，避免重复构建插件）
    val markwon = remember {
        Markwon.builder(context)
            .usePlugin(CorePlugin.create())
            // 主题色映射：链接蓝 / 代码块液态玻璃背景 / 正文星光白
            .usePlugin(AetherThemePlugin())
            .usePlugin(TablePlugin.create(context))
            .usePlugin(TaskListPlugin.create(context))
            .usePlugin(StrikethroughPlugin.create())
            .usePlugin(LinkifyPlugin.create())
            // 语法高亮：使用 Prism4j Darkula 主题（深色代码块背景 + 浅色文字）
            // GrammarLocator 返回 null 时回退为「无 token 着色但保留主题样式」
            .usePlugin(
                SyntaxHighlightPlugin.create(
                    Prism4j(NoOpGrammarLocator),
                    Prism4jThemeDarkula.create()
                )
            )
            .build()
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            TextView(ctx).apply {
                // 正文颜色：星光白
                setTextColor(AetherColors.starlight.toArgb())
                // 字号与 Compose TextStyle 同步（Compose 用 sp，TextView 用 sp）
                textSize = style.fontSize.value
                // 允许链接点击
                movementMethod = LinkMovementMethod.getInstance()
                // 避免父布局对 padding 的二次干扰
                includeFontPadding = false
            }
        },
        update = { textView ->
            markwon.setMarkdown(textView, markdown)
        }
    )
}

/**
 * Aether 主题插件：通过 [AbstractMarkwonPlugin.configureTheme] 将 AetherColors 映射到 Markwon 配色。
 * - 链接 = ElectricBlue
 * - 代码文字 = Starlight
 * - 代码块背景 = LiquidGlass
 * - 列表项 = Starlight
 *
 * 注意：LiquidGlass 自带 alpha，作为代码块背景时会与页面底色叠加。
 */
private class AetherThemePlugin : AbstractMarkwonPlugin() {
    override fun configureTheme(builder: MarkwonTheme.Builder) {
        builder.linkColor(AetherColors.electricBlue.toArgb())
            .codeTextColor(AetherColors.starlight.toArgb())
            .codeBackgroundColor(AetherColors.liquidGlass.toArgb())
            .thematicBreakColor(Color.DKGRAY)
            .listItemColor(AetherColors.starlight.toArgb())
    }
}

/**
 * 空实现的 GrammarLocator：对所有语言返回 null。
 *
 * - 行为：代码块仍以 Prism4jThemeDarkula 主题样式渲染（深色背景 + 等宽字体），
 *   但不会按 token 类型着色。
 * - 扩展：若需启用真实语法高亮，请使用 `prism4j-bundler` 注解处理器
 *   生成 `Prism4jGrammarLocator`，或在此处手动实现常见语言的 Grammar 装载。
 */
private object NoOpGrammarLocator : GrammarLocator {
    override fun grammar(prism4j: Prism4j, language: String): Prism4j.Grammar? = null
    override fun languages(): Set<String> = emptySet()
}
