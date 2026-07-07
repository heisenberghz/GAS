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
using System.Windows.Shapes;
using System.Windows.Threading;
using GAS.Core;
using GAS.Core.Data;
using GAS.Core.Models;

namespace GAS.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class DrawerWindow : Window
    {
        #region Win32 P/Invokes for Monitor Bounds
        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct MONITORINFOEX
        {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string szDevice;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
        #endregion

        private bool _isIntendedVisible;
        private string? _activeSessionId;
        private Guid? _activeLocalSessionId;
        private readonly Dictionary<string, Border> _trackedMessageBubbles = new();
        private readonly Dictionary<string, Border> _trackedToolCards = new();

        // Status strip state
        private DispatcherTimer? _elapsedTimer;
        private DateTime _sessionStartTime;
        private string _activeModel = "No model";
        private string _activeWorkspace = "No workspace";

        public DrawerWindow()
        {
            InitializeComponent();

            try
            {
                Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica);
            }
            catch
            {
                // Fallback to custom brush in XAML
            }

            LoadSessionHistory();
        }

        /// <summary>
        /// Shows the docked drawer window and runs the slide-in animation.
        /// </summary>
        public void ShowDrawer()
        {
            if (_isIntendedVisible) return;
            _isIntendedVisible = true;

            PositionDockedToRight();
            LoadSessionHistory();
            this.Show();
            this.Activate();

            var showSb = (Storyboard)Resources["ShowStoryboard"];
            showSb.Begin(this);
        }

        /// <summary>
        /// Runs the slide-out animation and hides the drawer window.
        /// </summary>
        public void HideDrawer()
        {
            if (!_isIntendedVisible) return;
            _isIntendedVisible = false;

            var hideSb = (Storyboard)Resources["HideStoryboard"];
            hideSb.Begin(this);
        }

        private void HideStoryboard_Completed(object sender, EventArgs e)
        {
            if (!_isIntendedVisible)
            {
                this.Hide();
            }
        }

        private void PositionDockedToRight()
        {
            var workArea = GetActiveScreenWorkArea();

            this.Left = workArea.Right - this.Width + 20; // 20px overlap for drop-shadow area
            this.Top = workArea.Top;
            this.Height = workArea.Height;
        }

        private Rect GetActiveScreenWorkArea()
        {
            var pt = new POINT();
            GetCursorPos(out pt);
            IntPtr hMonitor = MonitorFromPoint(pt, 1 /* MONITOR_DEFAULTTONEAREST */);

            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(mi);
            if (GetMonitorInfo(hMonitor, ref mi))
            {
                var source = PresentationSource.FromVisual(this);
                double dpiX = 1.0;
                double dpiY = 1.0;
                if (source?.CompositionTarget != null)
                {
                    dpiX = source.CompositionTarget.TransformToDevice.M11;
                    dpiY = source.CompositionTarget.TransformToDevice.M22;
                }

                double left = mi.rcWork.Left / dpiX;
                double top = mi.rcWork.Top / dpiY;
                double width = (mi.rcWork.Right - mi.rcWork.Left) / dpiX;
                double height = (mi.rcWork.Bottom - mi.rcWork.Top) / dpiY;

                return new Rect(left, top, width, height);
            }

            return new Rect(
                SystemParameters.WorkArea.Left,
                SystemParameters.WorkArea.Top,
                SystemParameters.WorkArea.Width,
                SystemParameters.WorkArea.Height
            );
        }

        /// <summary>
        /// Loads the lists of old sessions from SQLite.
        /// </summary>
        private void LoadSessionHistory()
        {
            try
            {
                using var db = new GASDbContext();
                var sessions = db.Sessions
                    .OrderByDescending(s => s.CreatedAt)
                    .ToList();

                var displayList = sessions.Select(s => new SessionDisplayItem
                {
                    Id = s.Id.ToString(),
                    OpenCodeSessionId = s.OpenCodeSessionId,
                    Intent = s.Intent,
                    DateStr = s.CreatedAt.ToString("MMMM dd, h:mm tt"),
                    Icon = s.Status == SessionStatus.Completed ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24 : Wpf.Ui.Controls.SymbolRegular.Record24,
                    IconColor = s.Status == SessionStatus.Completed ? "#10B981" : "#8A8A8A"
                }).ToList();

                MockSessionsList.ItemsSource = displayList;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to load session history: {ex.Message}");
            }
        }

        /// <summary>
        /// Initializes the UI for a new active session.
        /// </summary>
        public void OnNewSessionStarted(string sessionId, Guid localSessionId, string prompt)
        {
            _activeSessionId = sessionId;
            _activeLocalSessionId = localSessionId;
            _trackedMessageBubbles.Clear();
            _trackedToolCards.Clear();
            MockMessagesPanel.Children.Clear();

            // Start elapsed timer
            _sessionStartTime = DateTime.Now;
            _elapsedTimer?.Stop();
            _elapsedTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _elapsedTimer.Tick += (s, e) =>
            {
                var elapsed = DateTime.Now - _sessionStartTime;
                ElapsedLabel.Text = elapsed.TotalSeconds < 60
                    ? $"{(int)elapsed.TotalSeconds}s"
                    : $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds}s";
                ElapsedLabel.Visibility = Visibility.Visible;
            };
            _elapsedTimer.Start();

            UpdateStatusStrip("Thinking", _activeModel, _activeWorkspace, null);

            // Render user's primary prompt
            AddUserMessageBubble(prompt);
            LoadSessionHistory();
        }

        /// <summary>
        /// Updates the live status strip shown below the drawer header.
        /// Call this whenever agent state, model, or workspace changes.
        /// </summary>
        public void UpdateStatusStrip(string state, string model, string workspace, TimeSpan? elapsed)
        {
            Dispatcher.Invoke(() =>
            {
                _activeModel = model ?? _activeModel;
                _activeWorkspace = workspace ?? _activeWorkspace;

                // State pill text and color
                string stateText;
                string stateColor;
                string stateBorder;
                switch (state?.ToLower())
                {
                    case "thinking":
                        stateText = "⊙ Thinking";
                        stateColor = "#D97706";    // amber
                        stateBorder = "#92400E";
                        break;
                    case "executing":
                        stateText = "⚙ Executing";
                        stateColor = "#6366F1";    // indigo
                        stateBorder = "#3730A3";
                        break;
                    case "waiting":
                        stateText = "⏳ Waiting";
                        stateColor = "#F59E0B";    // amber
                        stateBorder = "#92400E";
                        break;
                    case "completed":
                    case "idle":
                        stateText = "● Idle";
                        stateColor = "#475569";    // muted
                        stateBorder = "#334155";
                        _elapsedTimer?.Stop();
                        ElapsedLabel.Visibility = Visibility.Collapsed;
                        break;
                    case "error":
                        stateText = "✕ Error";
                        stateColor = "#EF4444";    // red
                        stateBorder = "#7F1D1D";
                        _elapsedTimer?.Stop();
                        ElapsedLabel.Visibility = Visibility.Collapsed;
                        break;
                    default:
                        stateText = "● Idle";
                        stateColor = "#475569";
                        stateBorder = "#334155";
                        break;
                }

                AgentStateLabel.Text = stateText;
                AgentStateLabel.Foreground = (Brush)new BrushConverter().ConvertFromString(stateColor)!;
                AgentStatePill.BorderBrush = (Brush)new BrushConverter().ConvertFromString(stateBorder)!;

                StatusModelLabel.Text = _activeModel;
                var workspaceName = System.IO.Path.GetFileName(_activeWorkspace.TrimEnd('\\', '/'));
                StatusWorkspaceLabel.Text = string.IsNullOrEmpty(workspaceName) ? _activeWorkspace : workspaceName;

                // Workspace header
                WorkspaceNameText.Text = string.IsNullOrEmpty(workspaceName) ? "GAS" : workspaceName;
                WorkspacePathText.Text = _activeWorkspace;

                if (elapsed.HasValue)
                {
                    var e = elapsed.Value;
                    ElapsedLabel.Text = e.TotalSeconds < 60
                        ? $"{(int)e.TotalSeconds}s"
                        : $"{(int)e.TotalMinutes}m {e.Seconds}s";
                    ElapsedLabel.Visibility = Visibility.Visible;
                }
            });
        }

        /// <summary>
        /// Updates the connection status dot and path label in the drawer header.
        /// </summary>
        public void UpdateConnectionStatus(bool connected, string workspacePath)
        {
            Dispatcher.Invoke(() =>
            {
                ConnectionDot.Fill = connected
                    ? (Brush)new BrushConverter().ConvertFromString("#10B981")!   // green
                    : (Brush)new BrushConverter().ConvertFromString("#F59E0B")!;  // amber reconnecting

                WorkspacePathText.Text = connected ? workspacePath : "Reconnecting...";
            });
        }

        /// <summary>
        /// Maps an OpenCode tool name to a human-readable activity label and icon glyph.
        /// </summary>
        private static (string label, string icon) GetToolDisplayLabel(string? toolName)
        {
            return (toolName?.ToLowerInvariant() ?? "") switch
            {
                var t when t.Contains("read_file") || t.Contains("read")     => ("Reading file",        "\uE8A5"),  // Page icon
                var t when t.Contains("write_file") || t.Contains("write")   => ("Writing file",        "\uE8D2"),  // Edit
                var t when t.Contains("create_file") || t.Contains("create") => ("Creating file",       "\uE8A5"),
                var t when t.Contains("delete_file") || t.Contains("delete") => ("Deleting file",       "\uE74D"),  // Trash
                var t when t.Contains("list_dir") || t.Contains("directory") => ("Listing directory",   "\uE8B7"),  // Folder
                var t when t.Contains("search")                              => ("Searching files",     "\uE721"),  // Search
                var t when t.Contains("bash") || t.Contains("run_command")
                         || t.Contains("execute")                            => ("Running command",     "\uE756"),  // Code
                var t when t.Contains("browser")                             => ("Browser automation", "\uE774"),  // Globe
                var t when t.Contains("git")                                 => ("Git operation",       "\uE8B3"),  // Branch-like
                var t when t.Contains("patch") || t.Contains("edit")        => ("Editing file",        "\uE8D2"),
                var t when t.Contains("glob")                                => ("Searching files",     "\uE721"),
                _                                                             => (toolName ?? "Tool",   "\uE8B7")
            };
        }

        /// <summary>
        /// Handles incoming SSE events forwarded by App.xaml.cs.
        /// </summary>
        public void HandleIncomingEvent(OpenCodeEvent ev)
        {
            if (string.IsNullOrEmpty(_activeSessionId)) return;

            if (ev.type == "message.part.updated")
            {
                ParseAndRenderPartUpdated(ev.properties);
            }
            else if (ev.type == "message.part.delta")
            {
                ParseAndRenderPartDelta(ev.properties);
            }
        }

        private void ParseAndRenderPartUpdated(JsonElement properties)
        {
            if (!properties.TryGetProperty("part", out var part))
            {
                part = properties;
            }

            var type = part.TryGetProperty("type", out var typeProp) ? typeProp.GetString() : string.Empty;
            var id = part.TryGetProperty("id", out var idProp) ? idProp.GetString() : string.Empty;
            if (string.IsNullOrEmpty(id))
            {
                id = properties.TryGetProperty("partID", out var pIdProp) ? pIdProp.GetString() : string.Empty;
            }

            if (type == "text")
            {
                var text = part.TryGetProperty("text", out var textProp) ? textProp.GetString() : string.Empty;
                if (!string.IsNullOrEmpty(text))
                {
                    AddOrUpdateAgentMessageBubble(id, text, false);
                }
            }
            else if (type == "reasoning")
            {
                var text = part.TryGetProperty("text", out var textProp) ? textProp.GetString() : string.Empty;
                if (!string.IsNullOrEmpty(text))
                {
                    AddOrUpdateAgentMessageBubble(id, text, true);
                }
            }
            else if (type == "tool")
            {
                RenderToolPart(part);
            }
        }

        private void ParseAndRenderPartDelta(JsonElement properties)
        {
            var partID = properties.TryGetProperty("partID", out var pIdProp) ? pIdProp.GetString() : string.Empty;
            var field = properties.TryGetProperty("field", out var fProp) ? fProp.GetString() : string.Empty;
            var delta = properties.TryGetProperty("delta", out var dProp) ? dProp.GetString() : string.Empty;

            if (string.IsNullOrEmpty(partID) || string.IsNullOrEmpty(delta)) return;

            var isReasoning = field == "reasoning";
            AppendDeltaToBubble(partID, delta, isReasoning);
        }

        private void RenderToolPart(JsonElement part)
        {
            if (!part.TryGetProperty("state", out var state))
            {
                state = part;
            }

            var toolName = state.TryGetProperty("tool", out var toolProp) ? toolProp.GetString() : "Tool";
            var status = state.TryGetProperty("status", out var statusProp) ? statusProp.GetString() : string.Empty;
            var toolCallID = state.TryGetProperty("id", out var idProp) ? idProp.GetString() : string.Empty;

            if (string.IsNullOrEmpty(toolCallID)) return;

            var inputSummary = string.Empty;
            if (state.TryGetProperty("input", out var inputProp))
            {
                inputSummary = inputProp.ValueKind == JsonValueKind.String 
                    ? inputProp.GetString() 
                    : inputProp.ToString();
            }

            var outputSummary = string.Empty;
            if (state.TryGetProperty("output", out var outputProp))
            {
                outputSummary = outputProp.ValueKind == JsonValueKind.String 
                    ? outputProp.GetString() 
                    : outputProp.ToString();
            }

            AddOrUpdateToolCard(toolCallID, toolName, status, inputSummary, outputSummary);
        }

        #region UI Rendering Helpers
        private void AddUserMessageBubble(string text)
        {
            var border = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(99, 102, 241)), // Indigo #6366F1
                CornerRadius = new CornerRadius(14, 14, 0, 14),
                HorizontalAlignment = HorizontalAlignment.Right,
                MaxWidth = 300,
                Margin = new Thickness(0, 4, 0, 4),
                Padding = new Thickness(14, 10, 14, 10)
            };

            var textBox = CreateSelectableTextBox(text, Brushes.White);
            textBox.FontFamily = new FontFamily("Segoe UI Variable Text");

            border.Child = textBox;
            MockMessagesPanel.Children.Add(border);
            ScrollToBottom();
        }

        private void AddOrUpdateAgentMessageBubble(string partID, string text, bool isReasoning)
        {
            if (_trackedMessageBubbles.TryGetValue(partID, out var existingBorder))
            {
                var textBox = FindVisualChild<TextBox>(existingBorder);
                if (textBox != null)
                {
                    textBox.Text = text;
                }
                return;
            }

            Border border;

            if (isReasoning)
            {
                // Reasoning: left amber accent stripe
                var outerBorder = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(24, 24, 29)),  // #18181D
                    CornerRadius = new CornerRadius(14, 14, 14, 0),
                    HorizontalAlignment = HorizontalAlignment.Left,
                    MaxWidth = 300,
                    Margin = new Thickness(0, 4, 0, 4),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(42, 42, 52)),  // #2A2A34
                    BorderThickness = new Thickness(1)
                };

                var innerGrid = new Grid();
                innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3) }); // amber stripe
                innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var stripe = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(245, 158, 11)), // amber
                    CornerRadius = new CornerRadius(14, 0, 0, 0),
                    Margin = new Thickness(0)
                };
                Grid.SetColumn(stripe, 0);
                innerGrid.Children.Add(stripe);

                var contentStack = new StackPanel { Margin = new Thickness(10, 10, 12, 10) };
                Grid.SetColumn(contentStack, 1);

                var label = new TextBlock
                {
                    Text = "\uD83E\uDDE0 Reasoning",
                    FontSize = 10,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Color.FromRgb(245, 158, 11)), // amber
                    Margin = new Thickness(0, 0, 0, 5)
                };
                contentStack.Children.Add(label);

                var body = CreateSelectableTextBox(text, new SolidColorBrush(Color.FromRgb(148, 163, 184))); // #94A3B8
                body.FontFamily = new FontFamily("Segoe UI Variable Text");
                contentStack.Children.Add(body);

                innerGrid.Children.Add(contentStack);
                outerBorder.Child = innerGrid;
                border = outerBorder;
            }
            else
            {
                // Regular agent message
                border = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(24, 24, 29)),  // #18181D
                    CornerRadius = new CornerRadius(14, 14, 14, 0),
                    HorizontalAlignment = HorizontalAlignment.Left,
                    MaxWidth = 300,
                    Margin = new Thickness(0, 4, 0, 4),
                    Padding = new Thickness(14, 10, 14, 10),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(42, 42, 52)),  // #2A2A34
                    BorderThickness = new Thickness(1)
                };

                var body = CreateSelectableTextBox(text, new SolidColorBrush(Color.FromRgb(226, 232, 240))); // #E2E8F0
                body.FontFamily = new FontFamily("Segoe UI Variable Text");
                border.Child = body;
            }

            MockMessagesPanel.Children.Add(border);
            _trackedMessageBubbles[partID] = border;

            // Save to database
            SaveLogToDatabase(isReasoning ? "thought" : "text", text);
            ScrollToBottom();
        }

        private void AppendDeltaToBubble(string partID, string delta, bool isReasoning)
        {
            if (_trackedMessageBubbles.TryGetValue(partID, out var existingBorder))
            {
                var textBox = FindVisualChild<TextBox>(existingBorder);
                if (textBox != null)
                {
                    textBox.Text += delta;
                }
                ScrollToBottom();
            }
            else
            {
                AddOrUpdateAgentMessageBubble(partID, delta, isReasoning);
            }
        }

        private void AddOrUpdateToolCard(string toolCallID, string? toolName, string? status, string? input, string? output)
        {
            var isNew = !_trackedToolCards.TryGetValue(toolCallID, out var card);

            var (displayLabel, iconGlyph) = GetToolDisplayLabel(toolName);

            // Status chip colors
            Color statusColor;
            string statusChipBg;
            string statusText;
            switch (status?.ToLower())
            {
                case "completed":
                    statusColor = Color.FromRgb(16, 185, 129);   // green
                    statusChipBg = "#052E16";
                    statusText = "Completed";
                    break;
                case "error":
                    statusColor = Color.FromRgb(239, 68, 68);    // red
                    statusChipBg = "#450A0A";
                    statusText = "Error";
                    break;
                default:
                    statusColor = Color.FromRgb(217, 119, 6);    // amber (running)
                    statusChipBg = "#451A03";
                    statusText = "Running…";
                    break;
            }

            if (isNew)
            {
                card = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(24, 24, 29)),   // #18181D
                    CornerRadius = new CornerRadius(10),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(42, 42, 52)),  // #2A2A34
                    BorderThickness = new Thickness(1),
                    Margin = new Thickness(0, 4, 0, 4),
                    Padding = new Thickness(12, 10, 12, 10)
                };

                var outerStack = new StackPanel();

                // Header row: icon + label + status chip
                var headerGrid = new Grid { Margin = new Thickness(0, 0, 0, 0) };
                headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                // Tool icon
                var iconBlock = new TextBlock
                {
                    Text = iconGlyph,
                    FontFamily = new FontFamily("Segoe MDL2 Assets"),
                    FontSize = 14,
                    Foreground = new SolidColorBrush(statusColor),
                    Margin = new Thickness(0, 0, 8, 0),
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(iconBlock, 0);
                headerGrid.Children.Add(iconBlock);

                // Activity label
                var labelBlock = new TextBlock
                {
                    Text = displayLabel,
                    FontSize = 12,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Color.FromRgb(241, 245, 249)),  // #F1F5F9
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(labelBlock, 1);
                headerGrid.Children.Add(labelBlock);

                // Status chip
                var chipBorder = new Border
                {
                    Background = (Brush)new BrushConverter().ConvertFromString(statusChipBg)!,
                    BorderBrush = new SolidColorBrush(statusColor),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(4),
                    Padding = new Thickness(6, 2, 6, 2),
                    VerticalAlignment = VerticalAlignment.Center
                };
                var chipLabel = new TextBlock
                {
                    Text = statusText,
                    FontSize = 10,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(statusColor)
                };
                chipBorder.Child = chipLabel;
                Grid.SetColumn(chipBorder, 2);
                headerGrid.Children.Add(chipBorder);

                outerStack.Children.Add(headerGrid);

                // Input/output detail (monospace, selectable)
                var detailText = !string.IsNullOrEmpty(input) ? input : "Executing…";
                if (detailText.Length > 300) detailText = detailText[..300] + "…";

                var detailBox = CreateSelectableTextBox(detailText,
                    new SolidColorBrush(Color.FromRgb(100, 116, 139)));  // #64748B
                detailBox.FontFamily = new FontFamily("Cascadia Mono, Consolas, Courier New");
                detailBox.FontSize = 11;
                detailBox.Margin = new Thickness(0, 6, 0, 0);
                outerStack.Children.Add(detailBox);

                card.Child = outerStack;
                MockMessagesPanel.Children.Add(card);
                _trackedToolCards[toolCallID] = card;
                ScrollToBottom();
            }
            else
            {
                // Update existing card: icon, chip, and output text
                var allTextBlocks = FindVisualChildren<TextBlock>(card).ToList();
                // allTextBlocks[0] = icon glyph, allTextBlocks[1] = activity label, allTextBlocks[2] = chip label
                if (allTextBlocks.Count > 0)
                {
                    allTextBlocks[0].Text = iconGlyph;
                    allTextBlocks[0].Foreground = new SolidColorBrush(statusColor);
                }
                if (allTextBlocks.Count > 2)
                {
                    allTextBlocks[2].Text = statusText;
                    allTextBlocks[2].Foreground = new SolidColorBrush(statusColor);
                }

                // Update chip border colors
                var chipBorders = FindVisualChildren<Border>(card)
                    .Where(b => b.CornerRadius.TopLeft == 4).ToList();
                if (chipBorders.Count > 0)
                {
                    chipBorders[0].BorderBrush = new SolidColorBrush(statusColor);
                    chipBorders[0].Background = (Brush)new BrushConverter().ConvertFromString(statusChipBg)!;
                }

                // Update detail/output text
                var textBox = FindVisualChild<TextBox>(card);
                if (textBox != null)
                {
                    var newText = !string.IsNullOrEmpty(output) ? output : (!string.IsNullOrEmpty(input) ? input : textBox.Text);
                    if (newText.Length > 300) newText = newText[..300] + "…";
                    textBox.Text = newText;
                }
            }

            // Save tool call details to database
            SaveLogToDatabase($"tool:{toolName}:{status}", string.IsNullOrEmpty(output) ? (input ?? "") : output);
        }

        private void SaveLogToDatabase(string kind, string content)
        {
            if (!_activeLocalSessionId.HasValue) return;
            try
            {
                using var db = new GASDbContext();
                var log = new LogEntry
                {
                    SessionId = _activeLocalSessionId.Value,
                    Kind = kind,
                    RawJson = content
                };
                db.LogEntries.Add(log);
                db.SaveChanges();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to save log entry: {ex.Message}");
            }
        }

        /// <summary>
        /// Creates a read-only TextBox styled to look like a TextBlock, but with
        /// full text selection support (Ctrl+C, right-click → Copy).
        /// </summary>
        private static TextBox CreateSelectableTextBox(string text, Brush foreground)
        {
            var textBox = new TextBox
            {
                Text = text,
                TextWrapping = TextWrapping.Wrap,
                Foreground = foreground,
                FontSize = 13,
                IsReadOnly = true,
                BorderThickness = new Thickness(0),
                Background = Brushes.Transparent,
                Padding = new Thickness(0),
                FocusVisualStyle = null,
                CaretBrush = Brushes.Transparent,
                SelectionBrush = new SolidColorBrush(Color.FromArgb(100, 99, 102, 241)),
                ContextMenu = new ContextMenu()
            };

            // Right-click context menu: Copy + Select All
            var copyItem = new MenuItem { Header = "Copy", Command = ApplicationCommands.Copy };
            var selectAllItem = new MenuItem { Header = "Select All", Command = ApplicationCommands.SelectAll };
            textBox.ContextMenu.Items.Add(copyItem);
            textBox.ContextMenu.Items.Add(selectAllItem);

            return textBox;
        }

        private void ScrollToBottom()
        {
            var scrollViewer = FindVisualChild<ScrollViewer>(MockMessagesPanel);
            scrollViewer?.ScrollToBottom();
        }

        private T? FindVisualChild<T>(DependencyObject obj) where T : DependencyObject
        {
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(obj); i++)
            {
                var child = VisualTreeHelper.GetChild(obj, i);
                if (child is T t)
                {
                    return t;
                }
                var childOfChild = FindVisualChild<T>(child);
                if (childOfChild != null)
                {
                    return childOfChild;
                }
            }
            return null;
        }

        private IEnumerable<T> FindVisualChildren<T>(DependencyObject obj) where T : DependencyObject
        {
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(obj); i++)
            {
                var child = VisualTreeHelper.GetChild(obj, i);
                if (child is T t)
                {
                    yield return t;
                }
                foreach (var childOfChild in FindVisualChildren<T>(child))
                {
                    yield return childOfChild;
                }
            }
        }
        #endregion

        private void SessionsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (MockSessionsList.SelectedItem is SessionDisplayItem selected)
            {
                _activeSessionId = selected.OpenCodeSessionId;
                if (Guid.TryParse(selected.Id, out var localId))
                {
                    _activeLocalSessionId = localId;
                }
                else
                {
                    _activeLocalSessionId = null;
                }

                _trackedMessageBubbles.Clear();
                _trackedToolCards.Clear();
                MockMessagesPanel.Children.Clear();

                try
                {
                    using var db = new GASDbContext();
                    var logs = db.LogEntries
                        .Where(l => l.SessionId == Guid.Parse(selected.Id))
                        .OrderBy(l => l.CreatedAt)
                        .ToList();

                    // Re-render user's prompt as first bubble
                    AddUserMessageBubble(selected.Intent);

                    foreach (var log in logs)
                    {
                        if (log.Kind == "text" || log.Kind == "thought")
                        {
                            AddOrUpdateAgentMessageBubble(log.Id.ToString(), log.RawJson, log.Kind == "thought");
                        }
                        else if (log.Kind.StartsWith("tool:"))
                        {
                            var parts = log.Kind.Split(':');
                            var toolName = parts.Length > 1 ? parts[1] : "Tool";
                            var status = parts.Length > 2 ? parts[2] : "completed";
                            AddOrUpdateToolCard(log.Id.ToString(), toolName, status, string.Empty, log.RawJson);
                        }
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Failed to load session logs: {ex.Message}");
                }
            }
        }

        private void Window_Deactivated(object sender, EventArgs e)
        {
            HideDrawer();
        }

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape)
            {
                HideDrawer();
                e.Handled = true;
            }
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
                UpdateWindowWidth(660);
            }
            else
            {
                HistoryColumn.Width = new GridLength(0);
                SplitterColumn.Width = new GridLength(0);
                HistoryPanel.Visibility = Visibility.Collapsed;
                SidebarSplitter.Visibility = Visibility.Collapsed;
                UpdateWindowWidth(420);
            }
        }

        private void UpdateWindowWidth(double targetWidth)
        {
            double oldWidth = this.Width;
            this.Width = targetWidth;
            this.Left = this.Left - (targetWidth - oldWidth);
        }

        private void HistorySearchTextBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            var searchText = HistorySearchTextBox.Text.Trim().ToLower();
            try
            {
                using var db = new GASDbContext();
                var sessions = db.Sessions
                    .OrderByDescending(s => s.CreatedAt)
                    .ToList();

                var displayList = sessions
                    .Where(s => string.IsNullOrEmpty(searchText) || s.Intent.ToLower().Contains(searchText))
                    .Select(s => new SessionDisplayItem
                    {
                        Id = s.Id.ToString(),
                        Intent = s.Intent,
                        DateStr = s.CreatedAt.ToString("MMMM dd, h:mm tt"),
                        Icon = s.Status == SessionStatus.Completed ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24 : Wpf.Ui.Controls.SymbolRegular.Record24,
                        IconColor = s.Status == SessionStatus.Completed ? "#10B981" : "#8A8A8A"
                    }).ToList();

                MockSessionsList.ItemsSource = displayList;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to filter session history: {ex.Message}");
            }
        }

        /// <summary>
        /// Prepares the UI when an existing session is resumed from the command bar.
        /// </summary>
        public void OnSessionResumed(string sessionId, Guid localSessionId)
        {
            _activeSessionId = sessionId;
            _activeLocalSessionId = localSessionId;
            _trackedMessageBubbles.Clear();
            _trackedToolCards.Clear();
            MockMessagesPanel.Children.Clear();

            try
            {
                using var db = new GASDbContext();
                var session = db.Sessions.Find(Guid.Parse(sessionId));
                if (session != null)
                {
                    AddUserMessageBubble(session.Intent);

                    var logs = db.LogEntries
                        .Where(l => l.SessionId == session.Id)
                        .OrderBy(l => l.CreatedAt)
                        .ToList();

                    foreach (var log in logs)
                    {
                        if (log.Kind == "text" || log.Kind == "thought")
                        {
                            AddOrUpdateAgentMessageBubble(log.Id.ToString(), log.RawJson, log.Kind == "thought");
                        }
                        else if (log.Kind.StartsWith("tool:"))
                        {
                            var parts = log.Kind.Split(':');
                            var toolName = parts.Length > 1 ? parts[1] : "Tool";
                            var status = parts.Length > 2 ? parts[2] : "completed";
                            AddOrUpdateToolCard(log.Id.ToString(), toolName, status, string.Empty, log.RawJson);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to resume session logs: {ex.Message}");
            }

            LoadSessionHistory();
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            HideDrawer();
        }

        private void SendButton_Click(object sender, RoutedEventArgs e)
        {
            SendMessage();
        }

        private void InputTextBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
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

            AddUserMessageBubble(text);
            SaveLogToDatabase("user", text);

            if (Application.Current is App app)
            {
                app.StartRealAgentRun(text, _activeSessionId);
            }
        }

        public class SessionDisplayItem
        {
            public string Id { get; set; } = string.Empty;
            public string? OpenCodeSessionId { get; set; }
            public string Intent { get; set; } = string.Empty;
            public string DateStr { get; set; } = string.Empty;
            public Wpf.Ui.Controls.SymbolRegular Icon { get; set; }
            public string IconColor { get; set; } = "#8A8A8A";
        }
    }
}

