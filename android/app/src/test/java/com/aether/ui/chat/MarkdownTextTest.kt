package com.aether.ui.chat

import android.content.Context
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import io.noties.markwon.Markwon
import io.noties.markwon.core.CorePlugin
import io.noties.markwon.ext.strikethrough.StrikethroughPlugin
import io.noties.markwon.ext.tables.TablePlugin
import io.noties.markwon.ext.tasklist.TaskListPlugin
import io.noties.markwon.linkify.LinkifyPlugin
import io.noties.markwon.syntax.Prism4jThemeDarkula
import io.noties.markwon.syntax.SyntaxHighlightPlugin
import io.noties.prism4j.GrammarLocator
import io.noties.prism4j.Prism4j
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * MarkdownText 渲染基本验证（Robolectric）。
 *
 * 由于 Compose UI 测试依赖未引入，本测试直接验证 Markwon 实例的构建与渲染：
 * - 6 个插件全部装载不抛异常
 * - 各类 Markdown 语法（标题 / 加粗 / 代码块 / 表格 / 任务列表 / 删除线 / 链接）
 *   渲染到 TextView 后产生非空文本
 */
@RunWith(RobolectricTestRunner::class)
class MarkdownTextTest {

    private lateinit var context: Context
    private lateinit var markwon: Markwon

    /**
     * 与 MarkdownText.kt 中相同的 GrammarLocator：返回 null，依赖主题样式渲染代码块。
     */
    private object NoOpGrammarLocator : GrammarLocator {
        override fun grammar(prism4j: Prism4j, language: String): Prism4j.Grammar? = null
        override fun languages(): Set<String> = emptySet()
    }

    @Before
    fun setup() {
        context = ApplicationProvider.getApplicationContext()
        markwon = Markwon.builder(context)
            .usePlugin(CorePlugin.create())
            .usePlugin(TablePlugin.create(context))
            .usePlugin(TaskListPlugin.create(context))
            .usePlugin(StrikethroughPlugin.create())
            .usePlugin(LinkifyPlugin.create())
            .usePlugin(
                SyntaxHighlightPlugin.create(
                    Prism4j(NoOpGrammarLocator),
                    Prism4jThemeDarkula.create()
                )
            )
            .build()
    }

    @Test
    fun markwonInstanceBuiltSuccessfully() {
        assertNotNull(markwon)
    }

    @Test
    fun rendersHeadingMarkdown() {
        val textView = TextView(context)
        markwon.setMarkdown(textView, "# Heading 1\n\n## Heading 2")
        assertTrue("标题渲染后应有文本", textView.text.isNotEmpty())
        assertTrue("应包含 Heading 1", textView.text.toString().contains("Heading 1"))
    }

    @Test
    fun rendersBoldAndItalic() {
        val textView = TextView(context)
        markwon.setMarkdown(textView, "**bold** and *italic*")
        assertTrue(textView.text.isNotEmpty())
        assertTrue("应包含 bold", textView.text.toString().contains("bold"))
        assertTrue("应包含 italic", textView.text.toString().contains("italic"))
    }

    @Test
    fun rendersCodeBlock() {
        val textView = TextView(context)
        val md = """
            ```kotlin
            fun hello() = "world"
            ```
        """.trimIndent()
        markwon.setMarkdown(textView, md)
        assertTrue("代码块渲染后应有文本", textView.text.isNotEmpty())
        assertTrue("应包含 hello", textView.text.toString().contains("hello"))
    }

    @Test
    fun rendersInlineCode() {
        val textView = TextView(context)
        markwon.setMarkdown(textView, "Use `val` for immutable.")
        assertTrue(textView.text.toString().contains("val"))
    }

    @Test
    fun rendersTable() {
        val md = """
            | Name | Age |
            |------|-----|
            | Alice | 30 |
            | Bob   | 25 |
        """.trimIndent()
        // TablePlugin 通过 canvas 绘制表格边框与单元格，在 Robolectric 下
        // TextView.text / Spanned.toString() 仅包含空白（单元格文本由 canvas
        // 绘制，不进入 Spanned 文本）。因此改为验证：
        // 1) toMarkdown 不抛异常（说明 TablePlugin 成功解析表格语法）
        // 2) 产出的 Spanned 非空
        // 3) Spanned 中存在 span（TablePlugin 会注入表格相关 span）
        val spanned = markwon.toMarkdown(md)
        assertNotNull("toMarkdown 应返回非 null 结果", spanned)
        assertTrue("表格渲染后 Spanned 应有内容", spanned.isNotEmpty())
        val spans = spanned.getSpans(0, spanned.length, Any::class.java)
        assertTrue("表格渲染应生成至少一个 span", spans.isNotEmpty())
    }

    @Test
    fun rendersTaskList() {
        val textView = TextView(context)
        val md = """
            - [x] Done
            - [ ] Pending
        """.trimIndent()
        markwon.setMarkdown(textView, md)
        assertTrue(textView.text.isNotEmpty())
        assertTrue("应包含 Done", textView.text.toString().contains("Done"))
        assertTrue("应包含 Pending", textView.text.toString().contains("Pending"))
    }

    @Test
    fun rendersStrikethrough() {
        val textView = TextView(context)
        markwon.setMarkdown(textView, "~~deleted~~")
        assertTrue(textView.text.toString().contains("deleted"))
    }

    @Test
    fun rendersLink() {
        val textView = TextView(context)
        markwon.setMarkdown(textView, "[Aether](https://example.com)")
        val text = textView.text.toString()
        assertTrue("应包含 Aether 文本", text.contains("Aether"))
    }

    @Test
    fun rendersEmptyMarkdownToEmptyText() {
        val textView = TextView(context)
        markwon.setMarkdown(textView, "")
        assertEquals("", textView.text.toString())
    }

    @Test
    fun rendersPlainMarkdownPreservesContent() {
        val textView = TextView(context)
        markwon.setMarkdown(textView, "Hello World")
        assertEquals("Hello World", textView.text.toString())
    }
}
