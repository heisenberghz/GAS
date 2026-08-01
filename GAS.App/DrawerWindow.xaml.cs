using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using GAS.Core;
using GAS.Core.Data;
using GAS.Core.Models;

namespace GAS.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class DrawerWindow : Window
    {
        // ─────────────────────────────────────────────────────────────
        //  Win32 P/Invokes
        // ─────────────────────────────────────────────────────────────
        [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT pt);
        [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Auto)] static extern bool GetMonitorInfo(IntPtr h, ref MONITORINFOEX info);

        [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        struct MONITORINFOEX
        {
            public int cbSize;
            public RECT rcMonitor, rcWork;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
        }
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }

        // ─────────────────────────────────────────────────────────────
        //  State
        // ─────────────────────────────────────────────────────────────
        private bool _isIntendedVisible;
        private string? _activeSessionId;
        private Guid? _activeLocalSessionId;

        // Part tracking: partID → MessageRow wrapper
        private readonly Dictionary<string, MessageRow> _messageRows = new();
        // Tool tracking: toolCallID → ToolRow wrapper
        private readonly Dictionary<string, ToolRow> _toolRows = new();

        // Auto-scroll state
        private bool _userScrolledUp = false;
        private bool _isStreaming = false;

        // Status strip
        private DispatcherTimer? _elapsedTimer;
        private DateTime _sessionStartTime;
        private string _activeModel = "No model";
        private string _activeWorkspace = "No workspace";

        // ─────────────────────────────────────────────────────────────
        //  Nested types for tracking message rows
        // ─────────────────────────────────────────────────────────────
        private class MessageRow
        {
            public Border Container { get; init; } = null!;
            public StackPanel ContentPanel { get; init; } = null!;  // rebuilt from full text
            public string FullText { get; set; } = string.Empty;
            public bool IsReasoning { get; init; }
            // For streaming delta: we hold a live TextBlock that grows
            public StreamingBlock? StreamBlock { get; set; }
        }

        private class StreamingBlock
        {
            public Border Wrapper { get; init; } = null!;   // visible block in ContentPanel
            public System.Windows.Controls.TextBox TextBox { get; init; } = null!;
            public string Accumulated { get; set; } = string.Empty;
        }

        private class ToolRow
        {
            public Border Container { get; init; } = null!;
            public TextBlock StatusLabel { get; init; } = null!;
            public TextBlock IconLabel { get; init; } = null!;
            public Border ChipBorder { get; init; } = null!;
            public System.Windows.Controls.TextBox DetailBox { get; init; } = null!;
            public bool IsExpanded { get; set; } = true;
            public FrameworkElement ExpandableContent { get; init; } = null!;
        }

        // ─────────────────────────────────────────────────────────────
        //  Constructor
        // ─────────────────────────────────────────────────────────────
        public DrawerWindow()
        {
            InitializeComponent();
            try { Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica); }
            catch { /* fallback to XAML brush */ }
            LoadSessionHistory();
        }

        // ─────────────────────────────────────────────────────────────
        //  Show / Hide
        // ─────────────────────────────────────────────────────────────
        public void ShowDrawer()
        {
            if (_isIntendedVisible) return;
            _isIntendedVisible = true;
            PositionDockedToRight();
            LoadSessionHistory();
            Show();
            Activate();
            ((Storyboard)Resources["ShowStoryboard"]).Begin(this);
        }

        public void HideDrawer()
        {
            if (!_isIntendedVisible) return;
            _isIntendedVisible = false;
            ((Storyboard)Resources["HideStoryboard"]).Begin(this);
        }

        private void HideStoryboard_Completed(object sender, EventArgs e)
        {
            if (!_isIntendedVisible) Hide();
        }

        private void PositionDockedToRight()
        {
            var area = GetActiveScreenWorkArea();
            Left = area.Right - Width + 18;
            Top = area.Top;
            Height = area.Height;
        }

        private Rect GetActiveScreenWorkArea()
        {
            GetCursorPos(out var pt);
            IntPtr hMon = MonitorFromPoint(pt, 1);
            var mi = new MONITORINFOEX { cbSize = Marshal.SizeOf(typeof(MONITORINFOEX)) };
            if (GetMonitorInfo(hMon, ref mi))
            {
                var src = PresentationSource.FromVisual(this);
                double dx = src?.CompositionTarget?.TransformToDevice.M11 ?? 1.0;
                double dy = src?.CompositionTarget?.TransformToDevice.M22 ?? 1.0;
                return new Rect(mi.rcWork.Left / dx, mi.rcWork.Top / dy,
                                (mi.rcWork.Right - mi.rcWork.Left) / dx,
                                (mi.rcWork.Bottom - mi.rcWork.Top) / dy);
            }
            return SystemParameters.WorkArea;
        }

        // ─────────────────────────────────────────────────────────────
        //  Session Lifecycle
        // ─────────────────────────────────────────────────────────────
        public void OnNewSessionStarted(string sessionId, Guid localSessionId, string prompt)
        {
            _activeSessionId = sessionId;
            _activeLocalSessionId = localSessionId;
            ClearConversation();
            StartElapsedTimer();
            UpdateStatusStrip("Thinking", _activeModel, _activeWorkspace, null);
            AddUserMessage(prompt);
            LoadSessionHistory();
        }

        public void OnSessionResumed(string sessionId, Guid localSessionId)
        {
            _activeSessionId = sessionId;
            _activeLocalSessionId = localSessionId;
            ClearConversation();

            try
            {
                using var db = new GASDbContext();
                var session = db.Sessions.Find(localSessionId);
                if (session != null)
                {
                    AddUserMessage(session.Intent);
                    var logs = db.LogEntries.Where(l => l.SessionId == session.Id)
                                            .OrderBy(l => l.CreatedAt).ToList();
                    foreach (var log in logs)
                    {
                        if (log.Kind == "text" || log.Kind == "thought")
                            AddOrUpdateAgentMessage(log.Id.ToString(), log.RawJson, log.Kind == "thought", finalize: true);
                        else if (log.Kind.StartsWith("tool:"))
                        {
                            var p = log.Kind.Split(':');
                            AddOrUpdateToolCard(log.Id.ToString(), p.ElementAtOrDefault(1), p.ElementAtOrDefault(2) ?? "completed", string.Empty, log.RawJson);
                        }
                    }
                }
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Resume failed: {ex.Message}"); }

            LoadSessionHistory();
        }

        private void ClearConversation()
        {
            _messageRows.Clear();
            _toolRows.Clear();
            _userScrolledUp = false;
            _isStreaming = false;

            // Remove all message children, keep the placeholder
            var toRemove = ConversationPanel.Children.OfType<UIElement>()
                           .Where(c => c != EmptyStatePlaceholder).ToList();
            foreach (var c in toRemove) ConversationPanel.Children.Remove(c);

            EmptyStatePlaceholder.Visibility = Visibility.Visible;
            JumpToBottomButton.Visibility = Visibility.Collapsed;
        }

        // ─────────────────────────────────────────────────────────────
        //  Session History
        // ─────────────────────────────────────────────────────────────
        private void LoadSessionHistory()
        {
            try
            {
                using var db = new GASDbContext();
                var sessions = db.Sessions.OrderByDescending(s => s.CreatedAt).ToList();
                MockSessionsList.ItemsSource = sessions.Select(s => new SessionDisplayItem
                {
                    Id = s.Id.ToString(),
                    OpenCodeSessionId = s.OpenCodeSessionId,
                    Intent = s.Intent,
                    DateStr = s.CreatedAt.ToString("MMM dd, h:mm tt"),
                    Icon = s.Status == SessionStatus.Completed
                               ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24
                               : Wpf.Ui.Controls.SymbolRegular.Record24,
                    IconColor = s.Status == SessionStatus.Completed ? "#10B981" : "#64748B"
                }).ToList();
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"History load failed: {ex.Message}"); }
        }

        // ─────────────────────────────────────────────────────────────
        //  Status Strip
        // ─────────────────────────────────────────────────────────────
        public void UpdateStatusStrip(string state, string model, string workspace, TimeSpan? elapsed)
        {
            Dispatcher.Invoke(() =>
            {
                if (model != null) _activeModel = model;
                if (workspace != null) _activeWorkspace = workspace;

                (string text, string fg, string border, bool running) = state?.ToLower() switch
                {
                    "thinking"  => ("⊙ Thinking",   "#D97706", "#92400E", true),
                    "executing" => ("⚙ Executing",  "#6366F1", "#3730A3", true),
                    "waiting"   => ("⏳ Waiting",    "#F59E0B", "#92400E", true),
                    "error"     => ("✕ Error",       "#EF4444", "#7F1D1D", false),
                    _           => ("● Idle",        "#334155", "#1E293B", false),
                };

                AgentStateLabel.Text = text;
                AgentStateLabel.Foreground = Brush(fg);
                AgentStatePill.BorderBrush = Brush(border);

                _isStreaming = running;

                if (!running)
                {
                    _elapsedTimer?.Stop();
                    ElapsedLabel.Visibility = Visibility.Collapsed;
                    // Finalize all streaming blocks
                    foreach (var row in _messageRows.Values)
                        FinalizeStreamingBlock(row);
                }

                StatusModelLabel.Text = _activeModel;
                var wName = System.IO.Path.GetFileName(_activeWorkspace.TrimEnd('\\', '/'));
                StatusWorkspaceLabel.Text = string.IsNullOrEmpty(wName) ? _activeWorkspace : wName;
                var hName = string.IsNullOrEmpty(wName) ? "GAS" : wName;
                WorkspaceNameText.Text = hName;
                WorkspacePathText.Text = _activeWorkspace;

                if (elapsed.HasValue)
                {
                    var e = elapsed.Value;
                    ElapsedLabel.Text = e.TotalSeconds < 60 ? $"{(int)e.TotalSeconds}s"
                                                             : $"{(int)e.TotalMinutes}m {e.Seconds}s";
                    ElapsedLabel.Visibility = Visibility.Visible;
                }
            });
        }

        public void UpdateConnectionStatus(bool connected, string workspacePath)
        {
            Dispatcher.Invoke(() =>
            {
                ConnectionDot.Fill = connected ? Brush("#10B981") : Brush("#F59E0B");
                WorkspacePathText.Text = connected ? workspacePath : "Reconnecting…";
            });
        }

        private void StartElapsedTimer()
        {
            _sessionStartTime = DateTime.Now;
            _elapsedTimer?.Stop();
            _elapsedTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _elapsedTimer.Tick += (_, _) =>
            {
                var t = DateTime.Now - _sessionStartTime;
                ElapsedLabel.Text = t.TotalSeconds < 60 ? $"{(int)t.TotalSeconds}s"
                                                        : $"{(int)t.TotalMinutes}m {t.Seconds}s";
                ElapsedLabel.Visibility = Visibility.Visible;
            };
            _elapsedTimer.Start();
        }

        // ─────────────────────────────────────────────────────────────
        //  Event dispatch
        // ─────────────────────────────────────────────────────────────
        public void HandleIncomingEvent(OpenCodeEvent ev)
        {
            if (string.IsNullOrEmpty(_activeSessionId)) return;

            if (ev.type == "message.part.updated")
                ParseAndRenderPartUpdated(ev.properties);
            else if (ev.type == "message.part.delta")
                ParseAndRenderPartDelta(ev.properties);
            else if (ev.type is "session.error" or "auth.error" or "engine.error")
                AddOrUpdateAgentMessage("err_" + Guid.NewGuid(), $"⚠️ **Engine Error** ({ev.type}): {ev.ExtractErrorMessage()}", false, finalize: true);
        }

        private void ParseAndRenderPartUpdated(JsonElement props)
        {
            var part = props.TryGetProperty("part", out var p) ? p : props;
            var type = GetString(part, "type");
            var id = GetString(part, "id");
            if (string.IsNullOrEmpty(id)) id = GetString(props, "partID");
            if (string.IsNullOrEmpty(id)) return;

            if (type == "text")
            {
                var text = GetString(part, "text");
                if (!string.IsNullOrEmpty(text))
                    AddOrUpdateAgentMessage(id, text, false);
            }
            else if (type == "reasoning")
            {
                var text = GetString(part, "text");
                if (!string.IsNullOrEmpty(text))
                    AddOrUpdateAgentMessage(id, text, true);
            }
            else if (type == "tool")
            {
                RenderToolPart(part);
            }
        }

        private void ParseAndRenderPartDelta(JsonElement props)
        {
            var partID   = GetString(props, "partID");
            var field    = GetString(props, "field");
            var delta    = GetString(props, "delta");
            if (string.IsNullOrEmpty(partID) || string.IsNullOrEmpty(delta)) return;

            AppendDelta(partID, delta, field == "reasoning");
        }

        private void RenderToolPart(JsonElement part)
        {
            var state    = part.TryGetProperty("state", out var s) ? s : part;
            var toolName = GetString(state, "tool");
            var status   = GetString(state, "status");
            var id       = GetString(state, "id");
            if (string.IsNullOrEmpty(id)) return;

            var input  = state.TryGetProperty("input",  out var ip) ? (ip.ValueKind == JsonValueKind.String ? ip.GetString() : ip.ToString()) : string.Empty;
            var output = state.TryGetProperty("output", out var op) ? (op.ValueKind == JsonValueKind.String ? op.GetString() : op.ToString()) : string.Empty;

            AddOrUpdateToolCard(id, toolName, status, input, output);
        }

        // ─────────────────────────────────────────────────────────────
        //  User message
        // ─────────────────────────────────────────────────────────────
        private void AddUserMessage(string text)
        {
            Dispatcher.Invoke(() =>
            {
                EmptyStatePlaceholder.Visibility = Visibility.Collapsed;

                // ─── Separator / timestamp ───────────────────────────
                var ts = new TextBlock
                {
                    Text = DateTime.Now.ToString("h:mm tt"),
                    FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                    FontSize = 10,
                    Foreground = Brush("#1E293B"),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    Margin = new Thickness(0, 12, 0, 8)
                };
                ConversationPanel.Children.Add(ts);

                // ─── Message container ───────────────────────────────
                var outerGrid = new Grid { Margin = new Thickness(16, 0, 16, 0) };
                outerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40, GridUnitType.Star) });
                outerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60, GridUnitType.Star) });

                var bubble = new Border
                {
                    Background = new LinearGradientBrush(
                        Color.FromRgb(79, 70, 229),   // #4F46E5
                        Color.FromRgb(99, 102, 241),  // #6366F1
                        90),
                    CornerRadius = new CornerRadius(14, 14, 2, 14),
                    Padding = new Thickness(14, 10, 14, 10),
                    HorizontalAlignment = HorizontalAlignment.Right
                };

                var tb = new TextBox
                {
                    Text = text,
                    Foreground = Brushes.White,
                    FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                    FontSize = 13.5,
                    FontWeight = FontWeights.Normal,
                    Background = Brushes.Transparent,
                    BorderThickness = new Thickness(0),
                    Padding = new Thickness(0),
                    IsReadOnly = true,
                    TextWrapping = TextWrapping.Wrap,
                    FocusVisualStyle = null,
                    CaretBrush = Brushes.Transparent,
                    SelectionBrush = new SolidColorBrush(Color.FromArgb(80, 255, 255, 255)),
                    ContextMenu = BuildCopyContextMenu()
                };
                bubble.Child = tb;
                Grid.SetColumn(bubble, 1);
                outerGrid.Children.Add(bubble);
                ConversationPanel.Children.Add(outerGrid);
                ScrollToBottomIfNeeded();
            });
        }

        // ─────────────────────────────────────────────────────────────
        //  Agent messages (text / reasoning)
        // ─────────────────────────────────────────────────────────────
        private void AddOrUpdateAgentMessage(string partID, string text, bool isReasoning, bool finalize = false)
        {
            Dispatcher.Invoke(() =>
            {
                EmptyStatePlaceholder.Visibility = Visibility.Collapsed;

                if (_messageRows.TryGetValue(partID, out var row))
                {
                    // Update existing row
                    row.FullText = text;
                    if (row.StreamBlock != null)
                    {
                        row.StreamBlock.TextBox.Text = text;
                        row.StreamBlock.Accumulated = text;
                    }
                    if (finalize) FinalizeStreamingBlock(row);
                }
                else
                {
                    var container = isReasoning
                        ? BuildReasoningContainer(partID, text)
                        : BuildAgentContainer(partID, text);

                    ConversationPanel.Children.Add(container.Container);
                    _messageRows[partID] = container;

                    if (finalize) FinalizeStreamingBlock(container);
                }

                SaveLogToDatabase(isReasoning ? "thought" : "text", text);
                ScrollToBottomIfNeeded();
            });
        }

        private void AppendDelta(string partID, string delta, bool isReasoning)
        {
            Dispatcher.Invoke(() =>
            {
                if (_messageRows.TryGetValue(partID, out var row))
                {
                    if (row.StreamBlock != null)
                    {
                        row.StreamBlock.Accumulated += delta;
                        row.StreamBlock.TextBox.Text = row.StreamBlock.Accumulated;
                        row.FullText = row.StreamBlock.Accumulated;
                    }
                    else
                    {
                        // Shouldn't happen normally
                        row.FullText += delta;
                    }
                }
                else
                {
                    // First delta for this partID — create row with streaming block
                    EmptyStatePlaceholder.Visibility = Visibility.Collapsed;
                    var container = isReasoning
                        ? BuildReasoningContainer(partID, delta)
                        : BuildAgentContainer(partID, delta);
                    ConversationPanel.Children.Add(container.Container);
                    _messageRows[partID] = container;
                }

                ScrollToBottomIfNeeded();
            });
        }

        // ─────────────────────────────────────────────────────────────
        //  Container builders
        // ─────────────────────────────────────────────────────────────
        private MessageRow BuildAgentContainer(string partID, string text)
        {
            var outerBorder = new Border
            {
                Margin = new Thickness(16, 4, 16, 4)
            };

            var contentPanel = new StackPanel();

            // Agent name badge
            var badge = BuildAgentBadge();
            contentPanel.Children.Add(badge);

            // Streaming text block (grows during streaming)
            var streamBox = BuildStreamingTextBox(text, "#CBD5E1");
            var streamWrapper = new Border { Padding = new Thickness(0, 4, 0, 0) };
            streamWrapper.Child = streamBox;
            contentPanel.Children.Add(streamWrapper);

            outerBorder.Child = contentPanel;

            var row = new MessageRow
            {
                Container = outerBorder,
                ContentPanel = contentPanel,
                FullText = text,
                IsReasoning = false,
                StreamBlock = new StreamingBlock
                {
                    Wrapper = streamWrapper,
                    TextBox = streamBox,
                    Accumulated = text
                }
            };
            return row;
        }

        private MessageRow BuildReasoningContainer(string partID, string text)
        {
            // Outer border: left amber stripe
            var outerBorder = new Border
            {
                Margin = new Thickness(16, 4, 16, 4),
                Background = new SolidColorBrush(Color.FromRgb(17, 16, 24)),   // #111018
                CornerRadius = new CornerRadius(8),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 30, 42)),
                BorderThickness = new Thickness(1)
            };

            var innerGrid = new Grid();
            innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3) });
            innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var stripe = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(217, 119, 6)),  // amber
                CornerRadius = new CornerRadius(8, 0, 0, 8)
            };
            Grid.SetColumn(stripe, 0);
            innerGrid.Children.Add(stripe);

            var rightPanel = new StackPanel { Margin = new Thickness(12, 10, 12, 10) };
            Grid.SetColumn(rightPanel, 1);

            // ─── Header row (preview + expand toggle) ───
            var headerGrid = new Grid();
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var preview = BuildPreviewText(text, "🧠 Reasoning");
            Grid.SetColumn(preview, 0);
            headerGrid.Children.Add(preview);

            // Expand/collapse toggle
            bool[] expanded = { true };
            StackPanel? expandablePanel = null;
            var toggle = new Button
            {
                Content = "−",
                FontSize = 12,
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                Foreground = Brush("#475569"),
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4, 0, 4, 0),
                Cursor = Cursors.Hand,
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(toggle, 1);
            headerGrid.Children.Add(toggle);

            rightPanel.Children.Add(headerGrid);

            // Expandable content
            expandablePanel = new StackPanel { Margin = new Thickness(0, 6, 0, 0) };
            var streamBox = BuildStreamingTextBox(text, "#64748B", italic: true);
            var streamWrapper = new Border();
            streamWrapper.Child = streamBox;
            expandablePanel.Children.Add(streamWrapper);
            rightPanel.Children.Add(expandablePanel);

            toggle.Click += (_, _) =>
            {
                expanded[0] = !expanded[0];
                expandablePanel.Visibility = expanded[0] ? Visibility.Visible : Visibility.Collapsed;
                toggle.Content = expanded[0] ? "−" : "+";
                preview.Visibility = expanded[0] ? Visibility.Collapsed : Visibility.Visible;
            };

            innerGrid.Children.Add(rightPanel);
            outerBorder.Child = innerGrid;

            var row = new MessageRow
            {
                Container = outerBorder,
                ContentPanel = rightPanel,
                FullText = text,
                IsReasoning = true,
                StreamBlock = new StreamingBlock
                {
                    Wrapper = streamWrapper,
                    TextBox = streamBox,
                    Accumulated = text
                }
            };
            return row;
        }

        // ─────────────────────────────────────────────────────────────
        //  Finalize streaming → render markdown
        // ─────────────────────────────────────────────────────────────
        private void FinalizeStreamingBlock(MessageRow row)
        {
            if (row.StreamBlock == null) return;
            var finalText = row.FullText;
            var wrapper = row.StreamBlock.Wrapper;

            // Replace the streaming TextBox with a rendered markdown StackPanel
            var rendered = MarkdownRenderer.Render(finalText, muted: row.IsReasoning);
            wrapper.Child = rendered;
            row.StreamBlock = null;  // mark as finalized

            // Collapse reasoning by default
            if (row.IsReasoning)
            {
                // The expandable panel is the parent of wrapper; already managed by the toggle button
                // No extra action needed here – user can always expand again
            }
        }

        // ─────────────────────────────────────────────────────────────
        //  Tool cards
        // ─────────────────────────────────────────────────────────────
        private void AddOrUpdateToolCard(string id, string? toolName, string? status, string? input, string? output)
        {
            Dispatcher.Invoke(() =>
            {
                EmptyStatePlaceholder.Visibility = Visibility.Collapsed;

                var (displayLabel, iconGlyph) = ToolLabel(toolName);
                var (statusText, statusColor, chipBg) = ToolStatus(status);

                if (!_toolRows.TryGetValue(id, out var row))
                {
                    // Build new tool card
                    var card = new Border
                    {
                        Background = new SolidColorBrush(Color.FromRgb(14, 17, 22)),  // #0E1116
                        CornerRadius = new CornerRadius(8),
                        BorderBrush = new SolidColorBrush(Color.FromRgb(30, 30, 42)),
                        BorderThickness = new Thickness(1),
                        Margin = new Thickness(16, 3, 16, 3)
                    };

                    var outerStack = new StackPanel();

                    // Header
                    var header = new Border { Padding = new Thickness(12, 8, 12, 8) };
                    var headerGrid = new Grid();
                    headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                    var iconTb = new TextBlock
                    {
                        Text = iconGlyph,
                        FontFamily = new FontFamily("Segoe MDL2 Assets"),
                        FontSize = 13,
                        Foreground = Brush(statusColor),
                        Margin = new Thickness(0, 0, 8, 0),
                        VerticalAlignment = VerticalAlignment.Center
                    };
                    Grid.SetColumn(iconTb, 0);
                    headerGrid.Children.Add(iconTb);

                    var labelTb = new TextBlock
                    {
                        Text = displayLabel,
                        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                        FontSize = 12,
                        FontWeight = FontWeights.SemiBold,
                        Foreground = Brush("#CBD5E1"),
                        VerticalAlignment = VerticalAlignment.Center
                    };
                    Grid.SetColumn(labelTb, 1);
                    headerGrid.Children.Add(labelTb);

                    // Status chip
                    var chip = new Border
                    {
                        Background = Brush(chipBg),
                        BorderBrush = Brush(statusColor),
                        BorderThickness = new Thickness(1),
                        CornerRadius = new CornerRadius(4),
                        Padding = new Thickness(6, 2, 6, 2),
                        Margin = new Thickness(6, 0, 6, 0),
                        VerticalAlignment = VerticalAlignment.Center
                    };
                    var chipText = new TextBlock
                    {
                        Text = statusText,
                        FontSize = 10,
                        FontWeight = FontWeights.SemiBold,
                        Foreground = Brush(statusColor)
                    };
                    chip.Child = chipText;
                    Grid.SetColumn(chip, 2);
                    headerGrid.Children.Add(chip);

                    // Expand toggle
                    bool[] expanded = { true };
                    Border? expandArea = null;
                    var expandBtn = new Button
                    {
                        Content = "−",
                        FontSize = 11,
                        Foreground = Brush("#475569"),
                        Background = Brushes.Transparent,
                        BorderThickness = new Thickness(0),
                        Padding = new Thickness(2),
                        Cursor = Cursors.Hand
                    };
                    Grid.SetColumn(expandBtn, 3);
                    headerGrid.Children.Add(expandBtn);

                    header.Child = headerGrid;
                    outerStack.Children.Add(header);

                    // Expandable detail area
                    var detailText = !string.IsNullOrEmpty(input) ? input : "Executing…";
                    if (detailText?.Length > 400) detailText = detailText[..400] + "…";

                    var detailBox = new TextBox
                    {
                        Text = detailText,
                        FontFamily = new FontFamily("Cascadia Code, Cascadia Mono, Consolas"),
                        FontSize = 11.5,
                        Foreground = Brush("#475569"),
                        Background = Brushes.Transparent,
                        BorderThickness = new Thickness(0),
                        Padding = new Thickness(12, 6, 12, 10),
                        IsReadOnly = true,
                        TextWrapping = TextWrapping.Wrap,
                        FocusVisualStyle = null,
                        CaretBrush = Brushes.Transparent,
                        SelectionBrush = new SolidColorBrush(Color.FromArgb(80, 99, 102, 241)),
                        ContextMenu = BuildCopyContextMenu(),
                        MaxHeight = 160
                    };

                    expandArea = new Border
                    {
                        BorderBrush = new SolidColorBrush(Color.FromRgb(28, 28, 40)),
                        BorderThickness = new Thickness(0, 1, 0, 0)
                    };
                    expandArea.Child = detailBox;
                    outerStack.Children.Add(expandArea);

                    expandBtn.Click += (_, _) =>
                    {
                        expanded[0] = !expanded[0];
                        expandArea.Visibility = expanded[0] ? Visibility.Visible : Visibility.Collapsed;
                        expandBtn.Content = expanded[0] ? "−" : "+";
                    };

                    card.Child = outerStack;
                    ConversationPanel.Children.Add(card);

                    row = new ToolRow
                    {
                        Container = card,
                        StatusLabel = chipText,
                        IconLabel = iconTb,
                        ChipBorder = chip,
                        DetailBox = detailBox,
                        ExpandableContent = expandArea
                    };
                    _toolRows[id] = row;
                }
                else
                {
                    // Update existing card
                    row.IconLabel.Text = iconGlyph;
                    row.IconLabel.Foreground = Brush(statusColor);
                    row.StatusLabel.Text = statusText;
                    row.StatusLabel.Foreground = Brush(statusColor);
                    row.ChipBorder.BorderBrush = Brush(statusColor);
                    row.ChipBorder.Background = Brush(chipBg);

                    var newDetail = !string.IsNullOrEmpty(output) ? output : (!string.IsNullOrEmpty(input) ? input : row.DetailBox.Text);
                    if (newDetail?.Length > 400) newDetail = newDetail[..400] + "…";
                    row.DetailBox.Text = newDetail;
                }

                SaveLogToDatabase($"tool:{toolName}:{status}", string.IsNullOrEmpty(output) ? (input ?? "") : output!);
                ScrollToBottomIfNeeded();
            });
        }

        // ─────────────────────────────────────────────────────────────
        //  Scrolling
        // ─────────────────────────────────────────────────────────────
        private void ScrollToBottomIfNeeded()
        {
            if (!_userScrolledUp)
            {
                ConversationScrollViewer.ScrollToBottom();
            }
        }

        private void ConversationScrollViewer_ScrollChanged(object sender, ScrollChangedEventArgs e)
        {
            if (e.ExtentHeightChange > 0)
            {
                // Content grew (streaming) — only auto-scroll if user hasn't scrolled up
                if (!_userScrolledUp)
                    ConversationScrollViewer.ScrollToBottom();
            }
            else if (e.ViewportHeightChange == 0 && Math.Abs(e.VerticalChange) > 1)
            {
                // User manually scrolled
                double bottom = ConversationScrollViewer.ScrollableHeight;
                double offset = ConversationScrollViewer.VerticalOffset;
                _userScrolledUp = offset < bottom - 30;
                JumpToBottomButton.Visibility = _userScrolledUp ? Visibility.Visible : Visibility.Collapsed;
            }
        }

        private void ConversationScrollViewer_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
        {
            // If scrolling up, mark as user-scrolled
            if (e.Delta > 0) _userScrolledUp = true;
        }

        private void JumpToBottomButton_Click(object sender, RoutedEventArgs e)
        {
            _userScrolledUp = false;
            JumpToBottomButton.Visibility = Visibility.Collapsed;
            ConversationScrollViewer.ScrollToBottom();
        }

        // ─────────────────────────────────────────────────────────────
        //  Database
        // ─────────────────────────────────────────────────────────────
        private void SaveLogToDatabase(string kind, string content)
        {
            if (!_activeLocalSessionId.HasValue) return;
            try
            {
                using var db = new GASDbContext();
                db.LogEntries.Add(new LogEntry
                {
                    SessionId = _activeLocalSessionId.Value,
                    Kind = kind,
                    RawJson = content
                });
                db.SaveChanges();
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"DB log failed: {ex.Message}"); }
        }

        // ─────────────────────────────────────────────────────────────
        //  UI factory helpers
        // ─────────────────────────────────────────────────────────────
        private static UIElement BuildAgentBadge()
        {
            var row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Margin = new Thickness(0, 0, 0, 4)
            };
            var dot = new Border
            {
                Width = 20, Height = 20,
                Background = new LinearGradientBrush(Color.FromRgb(79, 70, 229), Color.FromRgb(139, 92, 246), 135),
                CornerRadius = new CornerRadius(10),
                Margin = new Thickness(0, 0, 6, 0)
            };
            dot.Child = new TextBlock
            {
                Text = "G",
                Foreground = Brushes.White,
                FontSize = 10,
                FontWeight = FontWeights.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            row.Children.Add(dot);
            row.Children.Add(new TextBlock
            {
                Text = "GAS",
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                Foreground = Brush("#475569"),
                VerticalAlignment = VerticalAlignment.Center
            });
            return row;
        }

        private static TextBlock BuildPreviewText(string text, string prefix)
        {
            var preview = text.Split('\n').FirstOrDefault(l => !string.IsNullOrWhiteSpace(l)) ?? text;
            if (preview.Length > 80) preview = preview[..80] + "…";
            return new TextBlock
            {
                Text = $"{prefix} · {preview}",
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                FontSize = 11,
                FontStyle = FontStyles.Italic,
                Foreground = Brush("#475569"),
                TextTrimming = TextTrimming.CharacterEllipsis,
                Visibility = Visibility.Collapsed   // visible only when collapsed
            };
        }

        private static System.Windows.Controls.TextBox BuildStreamingTextBox(string text, string hexColor, bool italic = false)
        {
            return new System.Windows.Controls.TextBox
            {
                Text = text,
                FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
                FontSize = 13.5,
                FontStyle = italic ? FontStyles.Italic : FontStyles.Normal,
                Foreground = Brush(hexColor),
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(0),
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                FocusVisualStyle = null,
                CaretBrush = Brushes.Transparent,
                SelectionBrush = new SolidColorBrush(Color.FromArgb(80, 99, 102, 241)),
                ContextMenu = BuildCopyContextMenu()
            };
        }

        private static ContextMenu BuildCopyContextMenu()
        {
            var menu = new ContextMenu();
            menu.Items.Add(new MenuItem { Header = "Copy",       Command = ApplicationCommands.Copy });
            menu.Items.Add(new MenuItem { Header = "Select All", Command = ApplicationCommands.SelectAll });
            return menu;
        }

        // ─────────────────────────────────────────────────────────────
        //  Tool meta helpers
        // ─────────────────────────────────────────────────────────────
        private static (string label, string icon) ToolLabel(string? name) =>
            (name?.ToLower() ?? "") switch
            {
                var t when t.Contains("read")      => ("Reading file",       "\uE8A5"),
                var t when t.Contains("write")     => ("Writing file",       "\uE8D2"),
                var t when t.Contains("create")    => ("Creating file",      "\uE8A5"),
                var t when t.Contains("delete")    => ("Deleting file",      "\uE74D"),
                var t when t.Contains("list")      => ("Listing directory",  "\uE8B7"),
                var t when t.Contains("search")    => ("Searching",          "\uE721"),
                var t when t.Contains("bash") || t.Contains("run") || t.Contains("exec") => ("Running command", "\uE756"),
                var t when t.Contains("browser")   => ("Browser automation", "\uE774"),
                var t when t.Contains("git")       => ("Git operation",      "\uE8B3"),
                var t when t.Contains("patch") || t.Contains("edit") => ("Editing file", "\uE8D2"),
                _                                  => (name ?? "Tool",       "\uE8B7")
            };

        private static (string text, string fg, string bg) ToolStatus(string? status) =>
            status?.ToLower() switch
            {
                "completed" => ("✓ Done",     "#10B981", "#052E16"),
                "error"     => ("✕ Error",    "#EF4444", "#450A0A"),
                _           => ("⋯ Running",  "#D97706", "#451A03")
            };

        // ─────────────────────────────────────────────────────────────
        //  Misc helpers
        // ─────────────────────────────────────────────────────────────
        private static SolidColorBrush Brush(string hex) =>
            (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;

        private static string? GetString(JsonElement el, string key) =>
            el.TryGetProperty(key, out var p) ? p.GetString() : null;

        // ─────────────────────────────────────────────────────────────
        //  Event handlers (UI controls)
        // ─────────────────────────────────────────────────────────────
        private void Window_Deactivated(object sender, EventArgs e) => HideDrawer();

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape) { HideDrawer(); e.Handled = true; }
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => HideDrawer();

        private void NewConversationButton_Click(object sender, RoutedEventArgs e)
        {
            _activeSessionId = null;
            _activeLocalSessionId = null;
            ClearConversation();
        }

        private bool _isHistoryOpen = false;

        private void ToggleHistoryButton_Click(object sender, RoutedEventArgs e)
        {
            _isHistoryOpen = !_isHistoryOpen;
            if (_isHistoryOpen)
            {
                HistoryColumn.Width = new GridLength(220);
                SplitterColumn.Width = GridLength.Auto;
                HistoryPanel.Visibility = Visibility.Visible;
                SidebarSplitter.Visibility = Visibility.Visible;
                UpdateWindowWidth(700);
            }
            else
            {
                HistoryColumn.Width = new GridLength(0);
                SplitterColumn.Width = new GridLength(0);
                HistoryPanel.Visibility = Visibility.Collapsed;
                SidebarSplitter.Visibility = Visibility.Collapsed;
                UpdateWindowWidth(460);
            }
        }

        private void UpdateWindowWidth(double target)
        {
            double old = Width;
            Width = target;
            Left = Left - (target - old);
        }

        private void HistorySearchTextBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            var q = HistorySearchTextBox.Text.Trim().ToLower();
            try
            {
                using var db = new GASDbContext();
                var sessions = db.Sessions.OrderByDescending(s => s.CreatedAt).ToList();
                MockSessionsList.ItemsSource = sessions
                    .Where(s => string.IsNullOrEmpty(q) || s.Intent.ToLower().Contains(q))
                    .Select(s => new SessionDisplayItem
                    {
                        Id = s.Id.ToString(),
                        OpenCodeSessionId = s.OpenCodeSessionId,
                        Intent = s.Intent,
                        DateStr = s.CreatedAt.ToString("MMM dd, h:mm tt"),
                        Icon = s.Status == SessionStatus.Completed
                                   ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24
                                   : Wpf.Ui.Controls.SymbolRegular.Record24,
                        IconColor = s.Status == SessionStatus.Completed ? "#10B981" : "#64748B"
                    }).ToList();
            }
            catch { }
        }

        private void SessionsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (MockSessionsList.SelectedItem is not SessionDisplayItem selected) return;
            _activeSessionId = selected.OpenCodeSessionId;
            _activeLocalSessionId = Guid.TryParse(selected.Id, out var g) ? g : null;
            ClearConversation();

            try
            {
                using var db = new GASDbContext();
                var logs = db.LogEntries
                             .Where(l => l.SessionId == Guid.Parse(selected.Id))
                             .OrderBy(l => l.CreatedAt).ToList();
                AddUserMessage(selected.Intent);
                foreach (var log in logs)
                {
                    if (log.Kind is "text" or "thought")
                        AddOrUpdateAgentMessage(log.Id.ToString(), log.RawJson, log.Kind == "thought", finalize: true);
                    else if (log.Kind.StartsWith("tool:"))
                    {
                        var p = log.Kind.Split(':');
                        AddOrUpdateToolCard(log.Id.ToString(), p.ElementAtOrDefault(1), p.ElementAtOrDefault(2) ?? "completed", string.Empty, log.RawJson);
                    }
                }
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Session load failed: {ex.Message}"); }
        }

        private void SendButton_Click(object sender, RoutedEventArgs e) => SendMessage();

        private void InputTextBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.None)
            {
                SendMessage();
                e.Handled = true;
            }
        }

        private void SendMessage()
        {
            var text = InputTextBox.Text.Trim();
            if (string.IsNullOrEmpty(text) || string.IsNullOrEmpty(_activeSessionId)) return;
            InputTextBox.Text = string.Empty;
            AddUserMessage(text);
            SaveLogToDatabase("user", text);
            (Application.Current as App)?.StartRealAgentRun(text, _activeSessionId);
        }

        // ─────────────────────────────────────────────────────────────
        //  Data model
        // ─────────────────────────────────────────────────────────────
        public class SessionDisplayItem
        {
            public string Id { get; set; } = string.Empty;
            public string? OpenCodeSessionId { get; set; }
            public string Intent { get; set; } = string.Empty;
            public string DateStr { get; set; } = string.Empty;
            public Wpf.Ui.Controls.SymbolRegular Icon { get; set; }
            public string IconColor { get; set; } = "#64748B";
        }
    }
}
