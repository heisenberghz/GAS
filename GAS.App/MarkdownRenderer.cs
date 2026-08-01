using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;

namespace GAS.App
{
    /// <summary>
    /// Renders a markdown string into WPF UIElements (TextBlock + Border combos)
    /// that are selectable and copyable. Supports:
    ///   • **bold**, *italic*, `inline code`, ~~strikethrough~~
    ///   • # headings
    ///   • ``` fenced code blocks
    ///   • - / * bullet lists
    ///   • Bare URLs
    /// </summary>
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    internal static class MarkdownRenderer
    {
        // ──────────────────────────────────────────────────────────────────
        //  Public API
        // ──────────────────────────────────────────────────────────────────

        /// <summary>Renders markdown into a StackPanel of WPF elements.</summary>
        public static StackPanel Render(string markdown, bool muted = false)
        {
            var panel = new StackPanel { Margin = new Thickness(0) };

            if (string.IsNullOrWhiteSpace(markdown))
                return panel;

            var blocks = ParseBlocks(markdown);
            foreach (var block in blocks)
                panel.Children.Add(BuildBlockElement(block, muted));

            return panel;
        }

        // ──────────────────────────────────────────────────────────────────
        //  Block-level parser
        // ──────────────────────────────────────────────────────────────────

        private enum BlockKind { Paragraph, Heading1, Heading2, Heading3, Code, BulletList, Divider }

        private class MdBlock
        {
            public BlockKind Kind { get; init; }
            public string Text { get; init; } = string.Empty;   // full text for para/heading
            public List<string> Items { get; init; } = new();   // lines for list
            public string Lang { get; init; } = string.Empty;   // code language
        }

        private static List<MdBlock> ParseBlocks(string markdown)
        {
            var blocks = new List<MdBlock>();
            var lines = markdown.Replace("\r\n", "\n").Split('\n');

            var i = 0;
            while (i < lines.Length)
            {
                var line = lines[i];

                // --- fenced code block ---
                if (line.TrimStart().StartsWith("```"))
                {
                    var lang = line.TrimStart().TrimStart('`').Trim();
                    var codeLines = new List<string>();
                    i++;
                    while (i < lines.Length && !lines[i].TrimStart().StartsWith("```"))
                    {
                        codeLines.Add(lines[i]);
                        i++;
                    }
                    i++; // skip closing ```
                    blocks.Add(new MdBlock { Kind = BlockKind.Code, Text = string.Join("\n", codeLines), Lang = lang });
                    continue;
                }

                // --- headings ---
                if (line.StartsWith("### "))
                {
                    blocks.Add(new MdBlock { Kind = BlockKind.Heading3, Text = line[4..] });
                    i++; continue;
                }
                if (line.StartsWith("## "))
                {
                    blocks.Add(new MdBlock { Kind = BlockKind.Heading2, Text = line[3..] });
                    i++; continue;
                }
                if (line.StartsWith("# "))
                {
                    blocks.Add(new MdBlock { Kind = BlockKind.Heading1, Text = line[2..] });
                    i++; continue;
                }

                // --- horizontal rule ---
                if (Regex.IsMatch(line.Trim(), @"^(-{3,}|_{3,}|\*{3,})$"))
                {
                    blocks.Add(new MdBlock { Kind = BlockKind.Divider });
                    i++; continue;
                }

                // --- bullet list ---
                if (line.TrimStart().StartsWith("- ") || line.TrimStart().StartsWith("* ") || line.TrimStart().StartsWith("• "))
                {
                    var items = new List<string>();
                    while (i < lines.Length &&
                           (lines[i].TrimStart().StartsWith("- ") || lines[i].TrimStart().StartsWith("* ") || lines[i].TrimStart().StartsWith("• ")))
                    {
                        var l = lines[i].TrimStart();
                        items.Add(l[2..]);
                        i++;
                    }
                    blocks.Add(new MdBlock { Kind = BlockKind.BulletList, Items = items });
                    continue;
                }

                // --- blank line → skip ---
                if (string.IsNullOrWhiteSpace(line))
                {
                    i++; continue;
                }

                // --- paragraph (collect consecutive non-special lines) ---
                var paraLines = new List<string>();
                while (i < lines.Length &&
                       !string.IsNullOrWhiteSpace(lines[i]) &&
                       !lines[i].TrimStart().StartsWith("```") &&
                       !lines[i].StartsWith("# ") &&
                       !lines[i].StartsWith("## ") &&
                       !lines[i].StartsWith("### ") &&
                       !lines[i].TrimStart().StartsWith("- ") &&
                       !lines[i].TrimStart().StartsWith("* "))
                {
                    paraLines.Add(lines[i]);
                    i++;
                }
                if (paraLines.Count > 0)
                    blocks.Add(new MdBlock { Kind = BlockKind.Paragraph, Text = string.Join(" ", paraLines) });
            }

            return blocks;
        }

        // ──────────────────────────────────────────────────────────────────
        //  WPF Element builder
        // ──────────────────────────────────────────────────────────────────

        private static UIElement BuildBlockElement(MdBlock block, bool muted)
        {
            switch (block.Kind)
            {
                case BlockKind.Code:
                    return BuildCodeBlock(block.Text, block.Lang);

                case BlockKind.Heading1:
                    return BuildTextBlock(block.Text, 19, FontWeights.Bold, muted ? "#94A3B8" : "#F1F5F9",
                                          new Thickness(0, 6, 0, 3));
                case BlockKind.Heading2:
                    return BuildTextBlock(block.Text, 16, FontWeights.SemiBold, muted ? "#94A3B8" : "#E2E8F0",
                                          new Thickness(0, 5, 0, 2));
                case BlockKind.Heading3:
                    return BuildTextBlock(block.Text, 14, FontWeights.SemiBold, muted ? "#94A3B8" : "#CBD5E1",
                                          new Thickness(0, 4, 0, 2));

                case BlockKind.BulletList:
                    return BuildBulletList(block.Items, muted);

                case BlockKind.Divider:
                    return new Border
                    {
                        Background = new SolidColorBrush(Color.FromRgb(42, 42, 52)),
                        Height = 1,
                        Margin = new Thickness(0, 6, 0, 6)
                    };

                default: // Paragraph
                    return BuildInlineTextBlock(block.Text, 13.5, muted ? "#94A3B8" : "#E2E8F0",
                                                 new Thickness(0, 2, 0, 2));
            }
        }

        // ─── Code block ─────────────────────────────────────────────────

        private static UIElement BuildCodeBlock(string code, string lang)
        {
            var outerBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(14, 17, 23)),  // #0E1117
                CornerRadius = new CornerRadius(6),
                BorderBrush = new SolidColorBrush(Color.FromRgb(48, 54, 61)),  // #30363D
                BorderThickness = new Thickness(1),
                Margin = new Thickness(0, 4, 0, 4)
            };

            var panel = new StackPanel();

            // Language header bar
            if (!string.IsNullOrEmpty(lang))
            {
                var header = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(22, 27, 34)),  // #161B22
                    Padding = new Thickness(12, 5, 12, 5),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(48, 54, 61)),
                    BorderThickness = new Thickness(0, 0, 0, 1)
                };
                var langBlock = new TextBlock
                {
                    Text = lang,
                    FontFamily = new FontFamily("Cascadia Code, Cascadia Mono, Consolas"),
                    FontSize = 10,
                    Foreground = new SolidColorBrush(Color.FromRgb(139, 148, 158))  // #8B949E
                };
                header.Child = langBlock;
                panel.Children.Add(header);
            }

            // Code content (selectable TextBox)
            var codeBox = new TextBox
            {
                Text = code,
                FontFamily = new FontFamily("Cascadia Code, Cascadia Mono, Consolas"),
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(201, 209, 217)),  // #C9D1D9
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(12, 10, 12, 10),
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                AcceptsReturn = true,
                FocusVisualStyle = null,
                CaretBrush = Brushes.Transparent,
                SelectionBrush = new SolidColorBrush(Color.FromArgb(80, 99, 102, 241)),
                ContextMenu = BuildCopyContextMenu()
            };
            panel.Children.Add(codeBox);
            outerBorder.Child = panel;
            return outerBorder;
        }

        // ─── Bullet list ────────────────────────────────────────────────

        private static UIElement BuildBulletList(List<string> items, bool muted)
        {
            var panel = new StackPanel { Margin = new Thickness(0, 2, 0, 2) };
            foreach (var item in items)
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 1, 0, 1) };
                var bullet = new TextBlock
                {
                    Text = "•",
                    FontSize = 13.5,
                    Foreground = new SolidColorBrush(Color.FromRgb(99, 102, 241)),  // indigo
                    Margin = new Thickness(4, 0, 8, 0),
                    VerticalAlignment = VerticalAlignment.Top
                };
                row.Children.Add(bullet);

                var tb = BuildInlineTextBox(item, muted ? "#94A3B8" : "#E2E8F0");
                tb.TextWrapping = TextWrapping.Wrap;
                row.Children.Add(tb);
                panel.Children.Add(row);
            }
            return panel;
        }

        // ─── Plain heading ───────────────────────────────────────────────

        private static UIElement BuildTextBlock(string text, double fontSize, FontWeight weight,
                                                 string hex, Thickness margin)
        {
            return new TextBlock
            {
                Text = StripInlineMarkup(text),
                FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI Variable Text, Segoe UI"),
                FontSize = fontSize,
                FontWeight = weight,
                Foreground = (Brush)new BrushConverter().ConvertFromString(hex)!,
                TextWrapping = TextWrapping.Wrap,
                Margin = margin
            };
        }

        // ─── Inline-markdown paragraph ───────────────────────────────────

        private static UIElement BuildInlineTextBlock(string text, double fontSize, string hexColor,
                                                       Thickness margin)
        {
            // Use a SelectableTextBox for copy support, but we add inline formatting via
            // a TextBlock with Inlines (inside a SelectionBox wrapper) for bold/italic/code.
            var tb = new TextBlock
            {
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                FontSize = fontSize,
                Foreground = (Brush)new BrushConverter().ConvertFromString(hexColor)!,
                TextWrapping = TextWrapping.Wrap,
                Margin = margin,
                LineHeight = fontSize * 1.65
            };

            BuildInlines(tb.Inlines, text, hexColor);
            return tb;
        }

        private static TextBox BuildInlineTextBox(string text, string hexColor)
        {
            return new TextBox
            {
                Text = StripInlineMarkup(text),
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                FontSize = 13.5,
                Foreground = (Brush)new BrushConverter().ConvertFromString(hexColor)!,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(0),
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                FocusVisualStyle = null,
                CaretBrush = Brushes.Transparent,
                SelectionBrush = new SolidColorBrush(Color.FromArgb(80, 99, 102, 241)),
                ContextMenu = BuildCopyContextMenu(),
                HorizontalAlignment = HorizontalAlignment.Stretch
            };
        }

        // ──────────────────────────────────────────────────────────────────
        //  Inline markdown parser → WPF Inlines
        // ──────────────────────────────────────────────────────────────────

        private static readonly Regex InlinePattern = new(
            @"(\*\*(.+?)\*\*|__(.+?)__)" +    // bold
            @"|(\*(.+?)\*|_(.+?)_)" +           // italic
            @"|(`(.+?)`)" +                     // inline code
            @"|(~~(.+?)~~)" +                   // strikethrough
            @"|(https?://\S+)",                 // URL
            RegexOptions.Compiled | RegexOptions.Singleline);

        private static void BuildInlines(InlineCollection inlines, string text, string baseColor)
        {
            var codeBack = new SolidColorBrush(Color.FromRgb(33, 38, 45));
            var codeColor = new SolidColorBrush(Color.FromRgb(255, 123, 114));  // reddish for code
            var urlColor = new SolidColorBrush(Color.FromRgb(88, 166, 255));    // blue

            int lastIndex = 0;
            foreach (Match m in InlinePattern.Matches(text))
            {
                // plain text before the match
                if (m.Index > lastIndex)
                    inlines.Add(new Run(text[lastIndex..m.Index]));

                if (m.Groups[1].Success)        // bold
                    inlines.Add(new Bold(new Run(m.Groups[2].Success ? m.Groups[2].Value : m.Groups[3].Value)));
                else if (m.Groups[4].Success)   // italic
                    inlines.Add(new Italic(new Run(m.Groups[5].Success ? m.Groups[5].Value : m.Groups[6].Value)));
                else if (m.Groups[7].Success)   // inline code
                {
                    var codeRun = new Run(m.Groups[8].Value)
                    {
                        FontFamily = new FontFamily("Cascadia Code, Cascadia Mono, Consolas"),
                        Foreground = codeColor,
                        Background = codeBack,
                        FontSize = 12
                    };
                    inlines.Add(codeRun);
                }
                else if (m.Groups[9].Success)   // strikethrough
                {
                    var st = new Run(m.Groups[10].Value);
                    var span = new Span(st);
                    span.TextDecorations.Add(TextDecorations.Strikethrough);
                    inlines.Add(span);
                }
                else if (m.Groups[11].Success)  // URL
                {
                    inlines.Add(new Run(m.Groups[11].Value) { Foreground = urlColor });
                }

                lastIndex = m.Index + m.Length;
            }

            // trailing plain text
            if (lastIndex < text.Length)
                inlines.Add(new Run(text[lastIndex..]));
        }

        // ──────────────────────────────────────────────────────────────────
        //  Helpers
        // ──────────────────────────────────────────────────────────────────

        private static string StripInlineMarkup(string text)
        {
            // Remove **bold**, *italic*, `code`, ~~strike~~
            return Regex.Replace(text, @"\*\*(.+?)\*\*|__(.+?)__|`(.+?)`|\*(.+?)\*|_(.+?)_|~~(.+?)~~",
                m => m.Groups.Cast<Group>().Skip(1).FirstOrDefault(g => g.Success)?.Value ?? m.Value);
        }

        private static ContextMenu BuildCopyContextMenu()
        {
            var menu = new ContextMenu();
            menu.Items.Add(new MenuItem { Header = "Copy", Command = ApplicationCommands.Copy });
            menu.Items.Add(new MenuItem { Header = "Select All", Command = ApplicationCommands.SelectAll });
            return menu;
        }
    }
}
