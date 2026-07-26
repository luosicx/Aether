using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using Aether.Windows.Services;
using Xunit;

namespace Aether.Windows.Tests;

/// <summary>MarkdownRenderer 单元测试：验证 Markdown → FlowDocument 转换的各类元素。</summary>
public class MarkdownRendererTest
{
    [WpfTheory]
    [InlineData("")]
    [InlineData(null)]
    public void Render_EmptyOrNull_ReturnsEmptyDocument(string? markdown)
    {
        var doc = MarkdownRenderer.RenderToFlowDocument(markdown ?? "");
        Assert.NotNull(doc);
        Assert.Empty(doc.Blocks);
    }

    [WpfTheory]
    [InlineData("# 一级标题", 24)]
    [InlineData("## 二级标题", 20)]
    [InlineData("### 三级标题", 18)]
    [InlineData("#### 四级标题", 16)]
    [InlineData("##### 五级标题", 14)]
    [InlineData("###### 六级标题", 12)]
    public void Render_Heading_GeneratesBoldParagraphWithCorrectFontSize(string markdown, double expectedFontSize)
    {
        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);

        var paragraph = Assert.Single(doc.Blocks.OfType<Paragraph>());
        Assert.Equal(expectedFontSize, paragraph.FontSize);
        Assert.Equal(System.Windows.FontWeights.Bold, paragraph.FontWeight);

        var run = Assert.Single(paragraph.Inlines.OfType<Run>());
        Assert.Contains("标题", run.Text);
    }

    [WpfFact]
    public void Render_Paragraph_ContainsRunWithText()
    {
        var doc = MarkdownRenderer.RenderToFlowDocument("这是一段普通文本。");

        var paragraph = Assert.Single(doc.Blocks.OfType<Paragraph>());
        var run = Assert.Single(paragraph.Inlines.OfType<Run>());
        Assert.Equal("这是一段普通文本。", run.Text);
    }

    [WpfFact]
    public void Render_FencedCodeBlock_ContainsBlockUIContainerWithText()
    {
        const string markdown = """
            ```csharp
            var x = 1;
            Console.WriteLine(x);
            ```
            """;

        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);

        var container = Assert.Single(doc.Blocks.OfType<BlockUIContainer>());
        // 容器中应包含 Border → TextBlock，文本中包含代码内容
        var textBlock = FindDescendantTextBlock(container.Child);
        Assert.NotNull(textBlock);
        Assert.Contains("var x = 1;", textBlock.Text);
        Assert.Contains("Console.WriteLine(x);", textBlock.Text);
        Assert.Equal("Consolas", textBlock.FontFamily.Source);
    }

    [WpfFact]
    public void Render_InlineCode_UsesMonospaceFont()
    {
        var doc = MarkdownRenderer.RenderToFlowDocument("这是 `inline code` 测试。");

        var paragraph = Assert.Single(doc.Blocks.OfType<Paragraph>());
        // inline code 包装在 InlineUIContainer + Border + TextBlock 中
        var inlineContainer = paragraph.Inlines.OfType<InlineUIContainer>().FirstOrDefault();
        Assert.NotNull(inlineContainer);
        var border = Assert.IsType<Border>(inlineContainer!.Child);
        var textBlock = Assert.IsType<TextBlock>(border.Child);
        Assert.Equal("inline code", textBlock.Text);
        Assert.Equal("Consolas", textBlock.FontFamily.Source);
    }

    [WpfFact]
    public void Render_Table_GeneratesWpfTableWithHeader()
    {
        const string markdown = """
            | 列A | 列B |
            |-----|-----|
            | 1 | 2 |
            | 3 | 4 |
            """;

        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);

        var table = Assert.Single(doc.Blocks.OfType<Table>());
        Assert.Single(table.RowGroups);
        var rowGroup = table.RowGroups[0];
        Assert.Equal(3, rowGroup.Rows.Count); // 1 header + 2 data

        // 表头加粗
        var headerRow = rowGroup.Rows[0];
        Assert.Equal(System.Windows.FontWeights.Bold, headerRow.FontWeight);
        Assert.Equal(2, headerRow.Cells.Count);

        // 数据行第一列包含 "1" / "3"
        var firstDataRow = rowGroup.Rows[1];
        var firstCellPara = Assert.Single(firstDataRow.Cells[0].Blocks.OfType<Paragraph>());
        var firstCellRun = Assert.Single(firstCellPara.Inlines.OfType<Run>());
        Assert.Equal("1", firstCellRun.Text);
    }

    [WpfFact]
    public void Render_TaskList_ContainsCheckBoxForEachItem()
    {
        const string markdown = """
            - [x] 已完成任务
            - [ ] 未完成任务
            """;

        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);

        var list = Assert.Single(doc.Blocks.OfType<List>());
        Assert.Equal(2, list.ListItems.Count);

        // 每个 item 内应有 InlineUIContainer + CheckBox
        foreach (var item in list.ListItems)
        {
            var para = Assert.Single(item.Blocks.OfType<Paragraph>());
            var checkBoxContainer = para.Inlines.OfType<InlineUIContainer>().FirstOrDefault();
            Assert.NotNull(checkBoxContainer);
            Assert.IsType<CheckBox>(checkBoxContainer.Child);
        }
    }

    [WpfFact]
    public void Render_UnorderedList_UsesDiscMarker()
    {
        const string markdown = """
            - 第一项
            - 第二项
            - 第三项
            """;

        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);

        var list = Assert.Single(doc.Blocks.OfType<List>());
        Assert.Equal(System.Windows.TextMarkerStyle.Disc, list.MarkerStyle);
        Assert.Equal(3, list.ListItems.Count);
    }

    [WpfFact]
    public void Render_OrderedList_UsesDecimalMarker()
    {
        const string markdown = """
            1. 第一项
            2. 第二项
            3. 第三项
            """;

        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);

        var list = Assert.Single(doc.Blocks.OfType<List>());
        Assert.Equal(System.Windows.TextMarkerStyle.Decimal, list.MarkerStyle);
        Assert.Equal(3, list.ListItems.Count);
    }

    [WpfFact]
    public void Render_Link_GeneratesHyperlinkWithNavigateUri()
    {
        var doc = MarkdownRenderer.RenderToFlowDocument("[示例链接](https://example.com)");

        var paragraph = Assert.Single(doc.Blocks.OfType<Paragraph>());
        var hyperlink = paragraph.Inlines.OfType<Hyperlink>().FirstOrDefault();
        Assert.NotNull(hyperlink);
        Assert.Equal(new Uri("https://example.com"), hyperlink!.NavigateUri);
        // 验证下划线装饰已设置（Hyperlink 默认带 Underline，MarkdownRenderer 显式赋值）
        Assert.NotNull(hyperlink.TextDecorations);
        Assert.True(hyperlink.TextDecorations.Count > 0);
    }

    [WpfFact]
    public void Render_BoldText_GeneratesBoldSpan()
    {
        var doc = MarkdownRenderer.RenderToFlowDocument("这是 **加粗** 文本");

        var paragraph = Assert.Single(doc.Blocks.OfType<Paragraph>());
        var boldSpan = paragraph.Inlines.OfType<Span>()
            .FirstOrDefault(s => s.FontWeight == System.Windows.FontWeights.Bold);
        Assert.NotNull(boldSpan);
        var run = Assert.Single(boldSpan.Inlines.OfType<Run>());
        Assert.Equal("加粗", run.Text);
    }

    [WpfFact]
    public void Render_ItalicText_GeneratesItalicSpan()
    {
        var doc = MarkdownRenderer.RenderToFlowDocument("这是 *斜体* 文本");

        var paragraph = Assert.Single(doc.Blocks.OfType<Paragraph>());
        var italicSpan = paragraph.Inlines.OfType<Span>()
            .FirstOrDefault(s => s.FontStyle == System.Windows.FontStyles.Italic);
        Assert.NotNull(italicSpan);
        var run = Assert.Single(italicSpan.Inlines.OfType<Run>());
        Assert.Equal("斜体", run.Text);
    }

    [WpfFact]
    public void Render_Strikethrough_GeneratesSpanWithStrikethrough()
    {
        var doc = MarkdownRenderer.RenderToFlowDocument("这是 ~~删除线~~ 文本");

        var paragraph = Assert.Single(doc.Blocks.OfType<Paragraph>());
        // TextDecorations.Strikethrough 是 frozen 单例，引用比较最稳健
        var strikeSpan = paragraph.Inlines.OfType<Span>()
            .FirstOrDefault(s => ReferenceEquals(s.TextDecorations, System.Windows.TextDecorations.Strikethrough));
        Assert.NotNull(strikeSpan);
        var run = Assert.Single(strikeSpan!.Inlines.OfType<Run>());
        Assert.Equal("删除线", run.Text);
    }

    [WpfFact]
    public void Render_QuoteBlock_ContainsSectionWithLeftBorder()
    {
        const string markdown = "> 这是引用块";

        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);

        var section = Assert.Single(doc.Blocks.OfType<Section>());
        Assert.True(section.BorderThickness.Left > 0);
    }

    [WpfFact]
    public void Render_MixedContent_ProducesMultipleBlocks()
    {
        const string markdown = """
            # 标题

            普通段落。

            ```python
            print("hello")
            ```

            - 列表项1
            - 列表项2
            """;

        var doc = MarkdownRenderer.RenderToFlowDocument(markdown);
        // 至少包含：标题段落、普通段落、代码块容器、列表
        Assert.True(doc.Blocks.Count >= 4, $"期望至少 4 个 Block，实际 {doc.Blocks.Count}");
        Assert.Contains(doc.Blocks, b => b is Paragraph);
        Assert.Contains(doc.Blocks, b => b is BlockUIContainer);
        Assert.Contains(doc.Blocks, b => b is List);
    }

    [WpfFact]
    public void Render_InvalidMarkdown_FallsBackToTextParagraph()
    {
        // 极端输入也不应抛异常
        var doc = MarkdownRenderer.RenderToFlowDocument("just plain text with no markdown elements");
        Assert.NotEmpty(doc.Blocks);
    }

    /// <summary>递归查找 Visual 树中的第一个 TextBlock（用于验证代码块内容）。</summary>
    private static TextBlock? FindDescendantTextBlock(object? root)
    {
        if (root is TextBlock tb) return tb;
        if (root is System.Windows.DependencyObject depObj)
        {
            foreach (var child in LogicalTreeHelper.GetChildren(depObj))
            {
                var found = FindDescendantTextBlock(child);
                if (found != null) return found;
            }
        }
        return null;
    }
}
