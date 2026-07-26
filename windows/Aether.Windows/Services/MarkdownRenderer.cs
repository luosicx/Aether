using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using Aether.Windows.Design;
using Markdig;
using Markdig.Extensions.Tables;
using Markdig.Extensions.TaskLists;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;

// 类型歧义消解：WPF 与 Markdig 都定义了 Block / Table / TableRow / TableCell / Inline，使用别名显式区分
using WpfBlock = System.Windows.Documents.Block;
using WpfTable = System.Windows.Documents.Table;
using WpfTableRow = System.Windows.Documents.TableRow;
using WpfTableCell = System.Windows.Documents.TableCell;
using WpfInline = System.Windows.Documents.Inline;
using MarkdigBlock = Markdig.Syntax.Block;
using MarkdigTable = Markdig.Extensions.Tables.Table;
using MarkdigTableRow = Markdig.Extensions.Tables.TableRow;
using MarkdigTableCell = Markdig.Extensions.Tables.TableCell;
using MarkdigInline = Markdig.Syntax.Inlines.Inline;

namespace Aether.Windows.Services;

/// <summary>
/// Markdown → WPF FlowDocument 渲染器。
/// 使用 Markdig 解析 Markdown，遍历 AST 转换为 FlowDocument 的 Block / Inline 结构。
/// 颜色复用 DesignTokens.AetherColors，保持与品牌色一致。
/// </summary>
public static class MarkdownRenderer
{
    /// <summary>Markdig 流水线（高级扩展：表格、任务列表、删除线、自动链接等）</summary>
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .Build();

    /// <summary>等宽字体（代码块 / 行内代码）</summary>
    private const string MonoFontFamily = "Consolas";

    /// <summary>正文默认字体大小</summary>
    private const double BodyFontSize = 14;

    /// <summary>缓存颜色 Color，避免重复创建 Brush</summary>
    private static class Colors
    {
        public static readonly Color Starlight = Color.FromArgb(0xFF, 0xE5, 0xE7, 0xEB);
        public static readonly Color DuskGray = Color.FromArgb(0xFF, 0x4B, 0x55, 0x63);
        public static readonly Color ElectricBlue = Color.FromArgb(0xFF, 0x00, 0xD4, 0xFF);
        public static readonly Color AetherPurple = Color.FromArgb(0xFF, 0x7C, 0x3A, 0xED);
        public static readonly Color LiquidGlass = Color.FromArgb(0x80, 0x1C, 0x1C, 0x2E);
        public static readonly Color CodeBackground = Color.FromArgb(0xFF, 0x1A, 0x1A, 0x2E);
        public static readonly Color InlineCodeBackground = Color.FromArgb(0xFF, 0x2A, 0x2A, 0x3E);
        public static readonly Color TableBorder = Color.FromArgb(0xFF, 0x4B, 0x55, 0x63);
    }

    /// <summary>把 Markdown 文本渲染为 FlowDocument。空字符串返回空文档。</summary>
    /// <param name="markdown">Markdown 源文本</param>
    public static FlowDocument RenderToFlowDocument(string markdown)
    {
        var doc = new FlowDocument
        {
            Background = Brushes.Transparent,
            Foreground = new SolidColorBrush(Colors.Starlight),
            FontSize = BodyFontSize,
            FontFamily = new FontFamily("Segoe UI"),
            PagePadding = new Thickness(0),
            TextAlignment = TextAlignment.Left
        };

        if (string.IsNullOrEmpty(markdown)) return doc;

        MarkdownDocument parsed;
        try
        {
            parsed = Markdown.Parse(markdown, Pipeline);
        }
        catch
        {
            // 解析失败时退化为纯文本段落
            doc.Blocks.Add(new Paragraph(new Run(markdown)));
            return doc;
        }

        foreach (var block in parsed)
        {
            var rendered = RenderBlock(block);
            if (rendered != null) doc.Blocks.Add(rendered);
        }

        return doc;
    }

    /// <summary>分发到具体的 Block 渲染方法。</summary>
    private static WpfBlock? RenderBlock(MarkdigBlock block)
    {
        switch (block)
        {
            case HeadingBlock h: return RenderHeading(h);
            case ParagraphBlock p: return RenderParagraph(p);
            case FencedCodeBlock fc: return RenderFencedCode(fc);
            case CodeBlock c: return RenderCode(c);
            case QuoteBlock q: return RenderQuote(q);
            case MarkdigTable t: return RenderTable(t);
            case ListBlock l: return RenderList(l, 0);
            case ThematicBreakBlock: return RenderThematicBreak();
            default: return RenderFallbackBlock(block);
        }
    }

    // ===== 标题 =====

    private static WpfBlock RenderHeading(HeadingBlock heading)
    {
        var para = new Paragraph
        {
            FontWeight = FontWeights.Bold,
            Foreground = new SolidColorBrush(Colors.Starlight),
            Margin = new Thickness(0, 8, 0, 4)
        };

        // H1=24, H2=20, H3=18, H4=16, H5=14, H6=12
        para.FontSize = heading.Level switch
        {
            1 => 24,
            2 => 20,
            3 => 18,
            4 => 16,
            5 => 14,
            _ => 12
        };

        // H1 / H2 使用 ElectricBlue 强调
        if (heading.Level <= 2)
        {
            para.Foreground = new SolidColorBrush(Colors.ElectricBlue);
        }

        if (heading.Inline != null)
        {
            AddInlines(para.Inlines, heading.Inline);
        }
        return para;
    }

    // ===== 段落 =====

    private static WpfBlock RenderParagraph(ParagraphBlock paragraph)
    {
        var para = new Paragraph
        {
            Margin = new Thickness(0, 4, 0, 4),
            Foreground = new SolidColorBrush(Colors.Starlight)
        };
        if (paragraph.Inline != null)
        {
            AddInlines(para.Inlines, paragraph.Inline);
        }
        return para;
    }

    // ===== 代码块 =====

    private static WpfBlock RenderFencedCode(FencedCodeBlock code)
    {
        var text = ExtractCodeText(code);
        return CreateCodeBlockContainer(text, code.Info ?? "");
    }

    private static WpfBlock RenderCode(CodeBlock code)
    {
        var text = ExtractCodeText(code);
        return CreateCodeBlockContainer(text, "");
    }

    /// <summary>提取代码块纯文本（保留缩进，去除首尾空行）。</summary>
    private static string ExtractCodeText(MarkdigBlock code)
    {
        var sb = new System.Text.StringBuilder();
        if (code is LeafBlock leaf && leaf.Lines.Lines != null)
        {
            foreach (var line in leaf.Lines.Lines)
            {
                if (line.Slice.Text == null) continue;
                sb.AppendLine(line.Slice.ToString());
            }
        }
        var result = sb.ToString().TrimEnd('\r', '\n');
        return result;
    }

    /// <summary>使用 BlockUIContainer + Border 包装代码块，实现深色背景 + 圆角。</summary>
    private static WpfBlock CreateCodeBlockContainer(string code, string language)
    {
        var textBlock = new TextBlock
        {
            Text = code,
            FontFamily = new FontFamily(MonoFontFamily),
            FontSize = 13,
            Foreground = new SolidColorBrush(Colors.Starlight),
            TextWrapping = TextWrapping.Wrap
        };

        var border = new Border
        {
            Background = new SolidColorBrush(Colors.CodeBackground),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(12),
            Margin = new Thickness(0, 6, 0, 6),
            Child = textBlock
        };

        // 语言标签（如有）
        if (!string.IsNullOrEmpty(language))
        {
            var langLabel = new TextBlock
            {
                Text = language,
                FontSize = 10,
                Foreground = new SolidColorBrush(Colors.DuskGray),
                Margin = new Thickness(0, 0, 0, 4)
            };

            var stack = new StackPanel();
            stack.Children.Add(langLabel);
            stack.Children.Add(border);
            return new BlockUIContainer(stack);
        }

        return new BlockUIContainer(border);
    }

    // ===== 引用块 =====

    private static WpfBlock RenderQuote(QuoteBlock quote)
    {
        var section = new Section
        {
            Margin = new Thickness(12, 4, 0, 4),
            Padding = new Thickness(8, 4, 0, 4),
            BorderBrush = new SolidColorBrush(Colors.AetherPurple),
            BorderThickness = new Thickness(2, 0, 0, 0),
            Foreground = new SolidColorBrush(Colors.DuskGray)
        };

        foreach (var sub in quote)
        {
            var rendered = RenderBlock(sub);
            if (rendered != null) section.Blocks.Add(rendered);
        }
        return section;
    }

    // ===== 表格 =====

    private static WpfBlock RenderTable(MarkdigTable table)
    {
        var wpfTable = new WpfTable
        {
            Margin = new Thickness(0, 6, 0, 6),
            BorderBrush = new SolidColorBrush(Colors.TableBorder),
            BorderThickness = new Thickness(1),
            CellSpacing = 0
        };

        // 列定义（如有）
        if (table.ColumnDefinitions.Count > 0)
        {
            foreach (var col in table.ColumnDefinitions)
            {
                var width = col.Alignment switch
                {
                    TableColumnAlign.Center => GridLength.Auto,
                    TableColumnAlign.Right => GridLength.Auto,
                    _ => GridLength.Auto
                };
                wpfTable.Columns.Add(new TableColumn { Width = width });
            }
        }

        var rowGroup = new TableRowGroup();
        bool isFirstRow = true;

        foreach (var row in table)
        {
            var wpfRow = new WpfTableRow();
            if (isFirstRow)
            {
                // 表头背景 + 加粗
                wpfRow.Background = new SolidColorBrush(Colors.LiquidGlass);
                wpfRow.FontWeight = FontWeights.Bold;
            }

            if (row is MarkdigTableRow tableRow)
            {
                foreach (var cell in tableRow)
                {
                    if (cell is MarkdigTableCell tableCell)
                    {
                        var cellContent = new WpfTableCell
                        {
                            BorderBrush = new SolidColorBrush(Colors.TableBorder),
                            BorderThickness = new Thickness(1),
                            Padding = new Thickness(8, 4, 8, 4)
                        };

                        var para = new Paragraph
                        {
                            Foreground = new SolidColorBrush(Colors.Starlight),
                            Margin = new Thickness(0)
                        };

                        foreach (var sub in tableCell)
                        {
                            if (sub is ParagraphBlock p && p.Inline != null)
                            {
                                AddInlines(para.Inlines, p.Inline);
                            }
                        }

                        cellContent.Blocks.Add(para);
                        wpfRow.Cells.Add(cellContent);
                    }
                }
            }

            rowGroup.Rows.Add(wpfRow);
            isFirstRow = false;
        }

        wpfTable.RowGroups.Add(rowGroup);
        return wpfTable;
    }

    // ===== 列表 =====

    /// <summary>
    /// 渲染列表。orderedListIndex 用于嵌套有序列表的起始编号。
    /// </summary>
    private static WpfBlock RenderList(ListBlock list, int startIndex)
    {
        var isOrdered = list.IsOrdered;
        var wpfList = new List
        {
            MarkerStyle = isOrdered ? TextMarkerStyle.Decimal : TextMarkerStyle.Disc,
            Margin = new Thickness(0, 4, 0, 4),
            Padding = new Thickness(20, 0, 0, 0),
            Foreground = new SolidColorBrush(Colors.Starlight)
        };

        int index = isOrdered
            ? (int.TryParse(list.OrderedStart, out var s) ? s : 1)
            : 0;

        foreach (MarkdigBlock item in list)
        {
            // Markdig 0.37.0 的 TaskList 是 LeafInline，不是 block 类型；
            // 任务列表项作为普通 ListItemBlock 处理，其 ParagraphBlock 内的
            // TaskList inline 会在 RenderInline 中渲染为 CheckBox。
            var listItem = new ListItem();
            // ListItemBlock 继承自 ContainerBlock，遍历其子 block 渲染
            if (item is ContainerBlock container)
            {
                foreach (MarkdigBlock sub in container)
                {
                    var rendered = RenderBlock(sub);
                    if (rendered != null) listItem.Blocks.Add(rendered);
                }
            }
            else
            {
                var rendered = RenderBlock(item);
                if (rendered != null) listItem.Blocks.Add(rendered);
            }
            wpfList.ListItems.Add(listItem);
            index++;
        }

        return wpfList;
    }

    // ===== 水平线 =====

    private static WpfBlock RenderThematicBreak()
    {
        var border = new Border
        {
            BorderBrush = new SolidColorBrush(Colors.DuskGray),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Margin = new Thickness(0, 8, 0, 8),
            Height = 1
        };
        return new BlockUIContainer(border);
    }

    /// <summary>未识别的 Block 类型回退为纯文本段落。</summary>
    private static WpfBlock RenderFallbackBlock(MarkdigBlock block)
    {
        if (block is LeafBlock leaf && leaf.Lines.Lines != null)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var line in leaf.Lines.Lines)
            {
                if (line.Slice.Text == null) continue;
                sb.AppendLine(line.Slice.ToString());
            }
            return new Paragraph(new Run(sb.ToString().TrimEnd()))
            {
                Foreground = new SolidColorBrush(Colors.Starlight)
            };
        }
        return new Paragraph();
    }

    // ===== Inline 渲染 =====

    /// <summary>递归遍历 ContainerInline，把所有 inline 添加到目标 InlineCollection。</summary>
    private static void AddInlines(InlineCollection target, ContainerInline container)
    {
        foreach (var inline in container)
        {
            var rendered = RenderInline(inline);
            if (rendered != null) target.Add(rendered);
        }
    }

    /// <summary>渲染单个 Inline 节点。ContainerInline 会递归。</summary>
    private static WpfInline? RenderInline(MarkdigInline inline)
    {
        switch (inline)
        {
            case LiteralInline literal:
                return new Run(literal.Content.ToString());

            case TaskList taskList:
                // Markdig 0.37.0 的 TaskList 是 LeafInline，渲染为禁用的 CheckBox
                return new InlineUIContainer(new CheckBox
                {
                    IsChecked = taskList.Checked,
                    IsEnabled = false,
                    Margin = new Thickness(0, 0, 8, 0),
                    VerticalAlignment = VerticalAlignment.Center
                });

            // EmphasisInline / LinkInline / DelimiterInline 均继承自 ContainerInline，
            // 必须在 ContainerInline 之前匹配，否则会被基类 case 吞掉（CS8120 不可达）。
            case EmphasisInline emphasis:
                return RenderEmphasis(emphasis);

            case CodeInline code:
                return RenderInlineCode(code);

            case LinkInline link:
                return RenderLink(link);

            case LineBreakInline:
                return new LineBreak();

            case HtmlInline html:
                return new Run(html.Tag) { Foreground = new SolidColorBrush(Colors.DuskGray) };

            // DelimiterInline 继承自 ContainerInline，由 ContainerInline case 递归处理其子节点。
            // Markdig 0.37.0 的 DelimiterInline 无 LiteralChild / Content 属性，不在此单独渲染。

            case ContainerInline container:
                // 嵌套容器：用 Span 包装，递归添加子节点（放最后，作为 ContainerInline 子类的兜底）
                var span = new Span();
                AddInlines(span.Inlines, container);
                return span;

            default:
                // 未知 inline 类型回退：尝试通过 ToString 显示，避免丢失内容
                var text = inline.ToString();
                return string.IsNullOrEmpty(text) ? null : new Run(text);
        }
    }

    /// <summary>渲染加粗 / 斜体 / 删除线。Markdig 通过 EmphasisInline 的 DelimiterChar 区分。</summary>
    private static WpfInline RenderEmphasis(EmphasisInline emphasis)
    {
        var content = new Span();
        AddInlines(content.Inlines, emphasis);

        // 双字符（** 或 __）= 加粗；单字符（* 或 _）= 斜体；~~ = 删除线
        var delim = emphasis.DelimiterChar;
        var delimCount = emphasis.DelimiterCount;

        if (delim == '~' && delimCount == 2)
        {
            // 删除线
            content.TextDecorations = TextDecorations.Strikethrough;
        }
        else if ((delim == '*' || delim == '_') && delimCount == 2)
        {
            content.FontWeight = FontWeights.Bold;
        }
        else if (delim == '*' || delim == '_')
        {
            content.FontStyle = FontStyles.Italic;
        }

        return content;
    }

    /// <summary>渲染行内代码：等宽字体 + 浅色背景。Span 支持 Background 属性（无 Padding，靠空格视觉留白）。</summary>
    private static WpfInline RenderInlineCode(CodeInline code)
    {
        // 用 InlineUIContainer + Border + TextBlock 实现真正的 padding 效果
        var textBlock = new TextBlock
        {
            Text = code.Content,
            FontFamily = new FontFamily(MonoFontFamily),
            FontSize = 13,
            Foreground = new SolidColorBrush(Colors.ElectricBlue),
            Background = new SolidColorBrush(Colors.InlineCodeBackground),
            Padding = new Thickness(4, 1, 4, 1)
        };
        var border = new Border { Child = textBlock };
        return new InlineUIContainer(border);
    }

    /// <summary>渲染超链接：ElectricBlue + 下划线。RequestNavigate 由 RichTextBox 处理。</summary>
    private static WpfInline RenderLink(LinkInline link)
    {
        var span = new Span();
        if (link.IsImage)
        {
            // 图片渲染复杂，回退为文本
            AddInlines(span.Inlines, link);
            return span;
        }

        var hyperlink = new Hyperlink();
        if (Uri.TryCreate(link.Url, UriKind.Absolute, out var uri))
        {
            hyperlink.NavigateUri = uri;
            hyperlink.RequestNavigate += (_, args) =>
            {
                try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(args.Uri.AbsoluteUri) { UseShellExecute = true }); }
                catch { /* 忽略打开失败 */ }
            };
        }
        hyperlink.Foreground = new SolidColorBrush(Colors.ElectricBlue);
        hyperlink.TextDecorations = TextDecorations.Underline;

        AddInlines(hyperlink.Inlines, link);
        return hyperlink;
    }
}

/// <summary>
/// 支持数据绑定的 RichTextBox。
/// 内置 RichTextBox.Document 不是 DependencyProperty，无法直接 Binding。
/// 通过附加 BindableDocument 依赖属性桥接，使 XAML 可写 Document="{Binding MarkdownDocument}"。
/// </summary>
public class BindableRichTextBox : RichTextBox
{
    /// <summary>可绑定的 FlowDocument 依赖属性。</summary>
    public static readonly DependencyProperty BindableDocumentProperty =
        DependencyProperty.Register(
            nameof(BindableDocument),
            typeof(FlowDocument),
            typeof(BindableRichTextBox),
            new PropertyMetadata(null, OnBindableDocumentChanged));

    static BindableRichTextBox()
    {
        // 默认 IsReadOnly / BorderThickness / Background，避免在每个使用处都设置
        IsReadOnlyProperty.OverrideMetadata(
            typeof(BindableRichTextBox),
            new FrameworkPropertyMetadata(true));
        BorderThicknessProperty.OverrideMetadata(
            typeof(BindableRichTextBox),
            new FrameworkPropertyMetadata(new Thickness(0)));
        BackgroundProperty.OverrideMetadata(
            typeof(BindableRichTextBox),
            new FrameworkPropertyMetadata(Brushes.Transparent));
    }

    /// <summary>可绑定的 FlowDocument。绑定到 ChatMessage.MarkdownDocument。</summary>
    public FlowDocument? BindableDocument
    {
        get => (FlowDocument?)GetValue(BindableDocumentProperty);
        set => SetValue(BindableDocumentProperty, value);
    }

    private static void OnBindableDocumentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is RichTextBox rtb)
        {
            rtb.Document = e.NewValue as FlowDocument ?? new FlowDocument();
        }
    }
}
