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
        private readonly Dictionary<string, Border> _trackedMessageBubbles = new();
        private readonly Dictionary<string, Border> _trackedToolCards = new();

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
        public void OnNewSessionStarted(string sessionId, string prompt)
        {
            _activeSessionId = sessionId;
            _trackedMessageBubbles.Clear();
            _trackedToolCards.Clear();
            MockMessagesPanel.Children.Clear();

            // Render user's primary prompt
            AddUserMessageBubble(prompt);
            LoadSessionHistory();
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
                CornerRadius = new CornerRadius(12, 12, 0, 12),
                HorizontalAlignment = HorizontalAlignment.Right,
                MaxWidth = 280,
                Margin = new Thickness(0, 5, 0, 5),
                Padding = new Thickness(12, 10, 12, 10)
            };

            var textBlock = new TextBlock
            {
                Text = text,
                TextWrapping = TextWrapping.Wrap,
                Foreground = Brushes.White,
                FontSize = 13
            };

            border.Child = textBlock;
            MockMessagesPanel.Children.Add(border);
            ScrollToBottom();
        }

        private void AddOrUpdateAgentMessageBubble(string partID, string text, bool isReasoning)
        {
            if (_trackedMessageBubbles.TryGetValue(partID, out var existingBorder))
            {
                var textBlock = FindVisualChild<TextBlock>(existingBorder);
                if (textBlock != null)
                {
                    textBlock.Text = text;
                }
                return;
            }

            var border = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(43, 43, 43)), // Dark grey
                CornerRadius = isReasoning ? new CornerRadius(12, 12, 12, 0) : new CornerRadius(12, 12, 12, 0),
                HorizontalAlignment = HorizontalAlignment.Left,
                MaxWidth = 280,
                Margin = new Thickness(0, 5, 0, 5),
                Padding = new Thickness(12, 10, 12, 10),
                BorderBrush = new SolidColorBrush(Color.FromRgb(61, 61, 61)),
                BorderThickness = new Thickness(1)
            };

            var stack = new StackPanel();

            if (isReasoning)
            {
                var label = new TextBlock
                {
                    Text = "Agent Thoughts:",
                    FontSize = 10,
                    FontWeight = FontWeights.Bold,
                    Foreground = new SolidColorBrush(Color.FromRgb(245, 158, 11)), // Orange
                    Margin = new Thickness(0, 0, 0, 4)
                };
                stack.Children.Add(label);
            }

            var body = new TextBlock
            {
                Text = text,
                TextWrapping = TextWrapping.Wrap,
                Foreground = new SolidColorBrush(Color.FromRgb(209, 213, 219)),
                FontSize = 13
            };
            stack.Children.Add(body);

            border.Child = stack;
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
                var textBlock = FindVisualChild<TextBlock>(existingBorder);
                if (textBlock != null)
                {
                    textBlock.Text += delta;
                }
                ScrollToBottom();
            }
            else
            {
                AddOrUpdateAgentMessageBubble(partID, delta, isReasoning);
            }
        }

        private void AddOrUpdateToolCard(string toolCallID, string toolName, string status, string input, string output)
        {
            var isNew = !_trackedToolCards.TryGetValue(toolCallID, out var card);
            
            var statusColor = status == "completed" ? Color.FromRgb(16, 185, 129) : // Green
                              status == "error" ? Color.FromRgb(239, 68, 68) : // Red
                              Color.FromRgb(245, 158, 11); // Thinking Orange

            var iconCode = status == "completed" ? "\uE8FB" : // Checkmark
                            status == "error" ? "\uEA39" : // Error X
                            "\uE8B7"; // Gear

            if (isNew)
            {
                card = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(26, 26, 26)),
                    CornerRadius = new CornerRadius(8),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(51, 51, 51)),
                    BorderThickness = new Thickness(1),
                    Margin = new Thickness(0, 5, 0, 5),
                    Padding = new Thickness(10)
                };

                var grid = new Grid();
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var iconBlock = new TextBlock
                {
                    Text = iconCode,
                    FontFamily = new FontFamily("Segoe MDL2 Assets"),
                    FontSize = 16,
                    Foreground = new SolidColorBrush(statusColor),
                    Margin = new Thickness(0, 0, 10, 0),
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(iconBlock, 0);
                grid.Children.Add(iconBlock);

                var stack = new StackPanel();
                Grid.SetColumn(stack, 1);

                var headerBlock = new TextBlock
                {
                    Text = $"{toolName} ({status})",
                    FontSize = 11,
                    FontWeight = FontWeights.Bold,
                    Foreground = new SolidColorBrush(statusColor)
                };
                stack.Children.Add(headerBlock);

                var detailBlock = new TextBlock
                {
                    Text = string.IsNullOrEmpty(input) ? "Executing tool..." : input,
                    FontSize = 11,
                    Foreground = new SolidColorBrush(Color.FromRgb(138, 138, 138)),
                    TextWrapping = TextWrapping.Wrap
                };
                stack.Children.Add(detailBlock);

                grid.Children.Add(stack);
                card.Child = grid;

                MockMessagesPanel.Children.Add(card);
                _trackedToolCards[toolCallID] = card;
                ScrollToBottom();
            }
            else
            {
                // Update status, icon, and texts
                var iconBlock = FindVisualChild<TextBlock>(card);
                if (iconBlock != null)
                {
                    iconBlock.Text = iconCode;
                    iconBlock.Foreground = new SolidColorBrush(statusColor);
                }

                var textBlocks = FindVisualChildren<TextBlock>(card).ToList();
                if (textBlocks.Count > 1)
                {
                    textBlocks[1].Text = $"{toolName} ({status})";
                    textBlocks[1].Foreground = new SolidColorBrush(statusColor);
                }
                if (textBlocks.Count > 2 && !string.IsNullOrEmpty(output))
                {
                    textBlocks[2].Text = output;
                }
            }

            // Save tool call details to database
            SaveLogToDatabase($"tool:{toolName}:{status}", string.IsNullOrEmpty(output) ? input : output);
        }

        private void SaveLogToDatabase(string kind, string content)
        {
            if (string.IsNullOrEmpty(_activeSessionId)) return;
            try
            {
                using var db = new GASDbContext();
                var log = new LogEntry
                {
                    SessionId = Guid.Parse(_activeSessionId),
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
                _activeSessionId = selected.Id;
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

        public void OnSessionResumed(string sessionId)
        {
            _activeSessionId = sessionId;
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
            public string Intent { get; set; } = string.Empty;
            public string DateStr { get; set; } = string.Empty;
            public Wpf.Ui.Controls.SymbolRegular Icon { get; set; }
            public string IconColor { get; set; } = "#8A8A8A";
        }
    }
}

