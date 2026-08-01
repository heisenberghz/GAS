using System;
using System.Collections.Generic;
using System.IO;
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
using Microsoft.Web.WebView2.Core;

namespace GAS.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class DrawerWindow : Window
    {
        // ─────────────────────────────────────────────────────────────
        //  Win32
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

        // WebView2 ready state + message queue
        private bool _webViewReady = false;
        private readonly Queue<string> _scriptQueue = new();

        // Status strip
        private DispatcherTimer? _elapsedTimer;
        private DateTime _sessionStartTime;
        private string _currentModel     = "No model";
        private string _currentWorkspace = "";

        // ─────────────────────────────────────────────────────────────
        //  Constructor
        // ─────────────────────────────────────────────────────────────
        public DrawerWindow()
        {
            InitializeComponent();
            try { Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica); }
            catch { /* WPF-UI Mica fallback */ }
            InitWebView();
            LoadSessionHistory();
        }

        // ─────────────────────────────────────────────────────────────
        //  WebView2 initialisation
        // ─────────────────────────────────────────────────────────────
        private async void InitWebView()
        {
            try
            {
                var dataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "GAS", "WebView2");

                var env = await CoreWebView2Environment.CreateAsync(
                    userDataFolder: dataFolder);

                await ConversationView.EnsureCoreWebView2Async(env);

                // Background matches the HTML (#0C0C0F)
                ConversationView.DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 12, 12, 15);

                // Disable right-click context menu (we handle copy via our own UI)
                ConversationView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                ConversationView.CoreWebView2.Settings.IsStatusBarEnabled = false;
                ConversationView.CoreWebView2.Settings.AreDevToolsEnabled = false;

                // Load the conversation HTML
                ConversationView.CoreWebView2.NavigateToString(ConversationHtml.GetHtml());
                // NavigationCompleted will set _webViewReady = true and flush _scriptQueue
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"WebView2 init failed: {ex.Message}");
            }
        }

        private void ConversationView_NavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            _webViewReady = true;
            // Flush any messages that arrived before WebView2 was ready
            while (_scriptQueue.Count > 0)
                _ = ConversationView.CoreWebView2.ExecuteScriptAsync(_scriptQueue.Dequeue());
        }

        // ─────────────────────────────────────────────────────────────
        //  JS bridge
        // ─────────────────────────────────────────────────────────────
        private void JS(string method, object payload)
        {
            var script = ConversationHtml.BuildCall(method, payload);
            Dispatcher.Invoke(() =>
            {
                if (_webViewReady && ConversationView.CoreWebView2 != null)
                    _ = ConversationView.CoreWebView2.ExecuteScriptAsync(script);
                else
                    _scriptQueue.Enqueue(script);
            });
        }

        private void JSRaw(string script)
        {
            Dispatcher.Invoke(() =>
            {
                if (_webViewReady && ConversationView.CoreWebView2 != null)
                    _ = ConversationView.CoreWebView2.ExecuteScriptAsync(script);
                else
                    _scriptQueue.Enqueue(script);
            });
        }

        // ─────────────────────────────────────────────────────────────
        //  Show / Hide with animation
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
            var area = GetWorkArea();
            Left   = area.Right - Width + 18;
            Top    = area.Top;
            Height = area.Height;
        }

        private Rect GetWorkArea()
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
        //  Session lifecycle
        // ─────────────────────────────────────────────────────────────
        public void OnNewSessionStarted(string sessionId, Guid localSessionId, string prompt)
        {
            _activeSessionId     = sessionId;
            _activeLocalSessionId = localSessionId;
            JSRaw("window.gasAPI.clearConversation()");
            StartElapsedTimer();
            UpdateStatusStrip("Thinking", _currentModel, _currentWorkspace, null);
            AddUserMessage(prompt);
            LoadSessionHistory();
        }

        public void OnSessionResumed(string sessionId, Guid localSessionId)
        {
            _activeSessionId     = sessionId;
            _activeLocalSessionId = localSessionId;
            JSRaw("window.gasAPI.clearConversation()");

            try
            {
                using var db = new GASDbContext();
                var session = db.Sessions.Find(localSessionId);
                if (session == null) return;

                AddUserMessage(session.Intent);

                var logs = db.LogEntries
                             .Where(l => l.SessionId == session.Id)
                             .OrderBy(l => l.CreatedAt)
                             .ToList();

                foreach (var log in logs)
                {
                    if (log.Kind is "text" or "thought")
                    {
                        JS("gasAPI.onPartUpdated", new
                        {
                            partID = log.Id.ToString(),
                            type   = log.Kind == "thought" ? "reasoning" : "text",
                            text   = log.RawJson
                        });
                    }
                    else if (log.Kind.StartsWith("tool:"))
                    {
                        var p = log.Kind.Split(':');
                        JS("gasAPI.addTool", new
                        {
                            id     = log.Id.ToString(),
                            name   = p.ElementAtOrDefault(1) ?? "Tool",
                            status = p.ElementAtOrDefault(2) ?? "completed",
                            input  = (string?)null,
                            output = log.RawJson
                        });
                    }
                }
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Resume failed: {ex}"); }

            LoadSessionHistory();
        }

        // ─────────────────────────────────────────────────────────────
        //  Event dispatch from OpenCode
        // ─────────────────────────────────────────────────────────────
        public void HandleIncomingEvent(OpenCodeEvent ev)
        {
            if (string.IsNullOrEmpty(_activeSessionId)) return;

            switch (ev.type)
            {
                case "message.part.delta":
                    HandlePartDelta(ev.properties);
                    break;
                case "message.part.updated":
                    HandlePartUpdated(ev.properties);
                    break;
                case "session.error":
                case "auth.error":
                case "engine.error":
                    var errId = "err_" + Guid.NewGuid().ToString("N")[..8];
                    JS("gasAPI.onPartUpdated", new
                    {
                        partID = errId,
                        type   = "text",
                        text   = $"⚠️ **Error** `{ev.type}`: {ev.ExtractErrorMessage()}"
                    });
                    break;
            }
        }

        private void HandlePartDelta(JsonElement props)
        {
            var partID = GetStr(props, "partID");
            var field  = GetStr(props, "field");
            var delta  = GetStr(props, "delta");
            if (string.IsNullOrEmpty(partID) || string.IsNullOrEmpty(delta)) return;

            JS("gasAPI.onPartDelta", new
            {
                partID,
                delta,
                type = field == "reasoning" ? "reasoning" : "text"
            });
        }

        private void HandlePartUpdated(JsonElement props)
        {
            // part may be nested under "part" key
            var part = props.TryGetProperty("part", out var p) ? p : props;
            var type = GetStr(part, "type");
            var id   = GetStr(part, "id") ?? GetStr(props, "partID");
            if (string.IsNullOrEmpty(id)) return;

            if (type == "text")
            {
                var text = GetStr(part, "text") ?? string.Empty;
                JS("gasAPI.onPartUpdated", new { partID = id, type = "text", text });
                SaveLog("text", text);
            }
            else if (type == "reasoning")
            {
                var text = GetStr(part, "text") ?? string.Empty;
                JS("gasAPI.onPartUpdated", new { partID = id, type = "reasoning", text });
                SaveLog("thought", text);
            }
            else if (type == "tool")
            {
                var state   = part.TryGetProperty("state", out var s) ? s : part;
                var toolName = GetStr(state, "tool") ?? GetStr(state, "name") ?? "Tool";
                var status  = GetStr(state, "status") ?? "running";
                var input   = state.TryGetProperty("input",  out var inp) ? SafeStr(inp)  : null;
                var output  = state.TryGetProperty("output", out var out_) ? SafeStr(out_) : null;

                JS("gasAPI.addTool", new { id, name = toolName, status, input, output });
                SaveLog($"tool:{toolName}:{status}", output ?? input ?? string.Empty);
            }
        }

        // ─────────────────────────────────────────────────────────────
        //  Status strip
        // ─────────────────────────────────────────────────────────────
        public void UpdateStatusStrip(string state, string model, string workspace, TimeSpan? elapsed)
        {
            Dispatcher.Invoke(() =>
            {
                if (!string.IsNullOrEmpty(model))     _currentModel     = model;
                if (!string.IsNullOrEmpty(workspace)) _currentWorkspace = workspace;

                var (text, fg, borderHex, running) = state.ToLower() switch
                {
                    "thinking"  => ("⊙ Thinking",  "#D97706", "#92400E", true),
                    "executing" => ("⚙ Executing", "#6366F1", "#3730A3", true),
                    "waiting"   => ("⏳ Waiting",   "#F59E0B", "#92400E", true),
                    "error"     => ("✕ Error",      "#EF4444", "#7F1D1D", false),
                    _           => ("● Idle",       "#334155", "#1E293B", false),
                };

                AgentStateLabel.Text        = text;
                AgentStateLabel.Foreground  = Brush(fg);
                AgentStatePill.BorderBrush  = Brush(borderHex);
                StatusModelLabel.Text       = _currentModel;
                var wShort = System.IO.Path.GetFileName(_currentWorkspace.TrimEnd('\\', '/'));
                StatusWorkspaceLabel.Text   = string.IsNullOrEmpty(wShort) ? _currentWorkspace : wShort;
                WorkspaceNameText.Text      = string.IsNullOrEmpty(wShort) ? "GAS" : wShort;
                WorkspacePathText.Text      = _currentWorkspace;

                if (!running)
                {
                    _elapsedTimer?.Stop();
                    ElapsedLabel.Visibility = Visibility.Collapsed;
                }

                if (elapsed.HasValue)
                {
                    var e = elapsed.Value;
                    ElapsedLabel.Text       = e.TotalSeconds < 60 ? $"{(int)e.TotalSeconds}s"
                                                                   : $"{(int)e.TotalMinutes}m {e.Seconds}s";
                    ElapsedLabel.Visibility = Visibility.Visible;
                }
            });
        }

        public void UpdateConnectionStatus(bool connected, string workspacePath)
        {
            Dispatcher.Invoke(() =>
            {
                ConnectionDot.Fill   = connected ? Brush("#10B981") : Brush("#F59E0B");
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
                ElapsedLabel.Text       = t.TotalSeconds < 60 ? $"{(int)t.TotalSeconds}s"
                                                               : $"{(int)t.TotalMinutes}m {t.Seconds}s";
                ElapsedLabel.Visibility = Visibility.Visible;
            };
            _elapsedTimer.Start();
        }

        // ─────────────────────────────────────────────────────────────
        //  User message
        // ─────────────────────────────────────────────────────────────
        private void AddUserMessage(string text)
        {
            JS("gasAPI.addUserMessage", new
            {
                text,
                timestamp = DateTime.Now.ToString("h:mm tt")
            });
        }

        // ─────────────────────────────────────────────────────────────
        //  Session history (sidebar)
        // ─────────────────────────────────────────────────────────────
        private void LoadSessionHistory()
        {
            try
            {
                using var db = new GASDbContext();
                var sessions = db.Sessions.OrderByDescending(s => s.CreatedAt).ToList();
                Dispatcher.Invoke(() =>
                {
                    MockSessionsList.ItemsSource = sessions.Select(s => new SessionDisplayItem
                    {
                        Id               = s.Id.ToString(),
                        OpenCodeSessionId = s.OpenCodeSessionId,
                        Intent           = s.Intent,
                        DateStr          = s.CreatedAt.ToString("MMM dd, h:mm tt"),
                        Icon             = s.Status == SessionStatus.Completed
                                               ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24
                                               : Wpf.Ui.Controls.SymbolRegular.Record24,
                        IconColor        = s.Status == SessionStatus.Completed ? "#10B981" : "#64748B"
                    }).ToList();
                });
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"History load failed: {ex.Message}"); }
        }

        // ─────────────────────────────────────────────────────────────
        //  Database
        // ─────────────────────────────────────────────────────────────
        private void SaveLog(string kind, string content)
        {
            if (!_activeLocalSessionId.HasValue) return;
            try
            {
                using var db = new GASDbContext();
                db.LogEntries.Add(new LogEntry
                {
                    SessionId = _activeLocalSessionId.Value,
                    Kind      = kind,
                    RawJson   = content
                });
                db.SaveChanges();
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"DB log: {ex.Message}"); }
        }

        // ─────────────────────────────────────────────────────────────
        //  UI event handlers
        // ─────────────────────────────────────────────────────────────
        private void Window_Deactivated(object sender, EventArgs e) => HideDrawer();

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape) { HideDrawer(); e.Handled = true; }
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => HideDrawer();

        private void NewConversationButton_Click(object sender, RoutedEventArgs e)
        {
            _activeSessionId      = null;
            _activeLocalSessionId = null;
            JSRaw("window.gasAPI.clearConversation()");
        }

        private bool _isHistoryOpen = false;

        private void ToggleHistoryButton_Click(object sender, RoutedEventArgs e)
        {
            _isHistoryOpen = !_isHistoryOpen;
            if (_isHistoryOpen)
            {
                HistoryColumn.Width  = new GridLength(220);
                SplitterColumn.Width = GridLength.Auto;
                HistoryPanel.Visibility       = Visibility.Visible;
                SidebarSplitter.Visibility    = Visibility.Visible;
                UpdateWindowWidth(700);
            }
            else
            {
                HistoryColumn.Width  = new GridLength(0);
                SplitterColumn.Width = new GridLength(0);
                HistoryPanel.Visibility       = Visibility.Collapsed;
                SidebarSplitter.Visibility    = Visibility.Collapsed;
                UpdateWindowWidth(460);
            }
        }

        private void UpdateWindowWidth(double target)
        {
            double old = Width;
            Width = target;
            Left  = Left - (target - old);
        }

        private void HistorySearchTextBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            var q = HistorySearchTextBox.Text.Trim().ToLower();
            try
            {
                using var db = new GASDbContext();
                MockSessionsList.ItemsSource = db.Sessions
                    .OrderByDescending(s => s.CreatedAt).ToList()
                    .Where(s => string.IsNullOrEmpty(q) || s.Intent.ToLower().Contains(q))
                    .Select(s => new SessionDisplayItem
                    {
                        Id               = s.Id.ToString(),
                        OpenCodeSessionId = s.OpenCodeSessionId,
                        Intent           = s.Intent,
                        DateStr          = s.CreatedAt.ToString("MMM dd, h:mm tt"),
                        Icon             = s.Status == SessionStatus.Completed
                                               ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24
                                               : Wpf.Ui.Controls.SymbolRegular.Record24,
                        IconColor        = s.Status == SessionStatus.Completed ? "#10B981" : "#64748B"
                    }).ToList();
            }
            catch { }
        }

        private void SessionsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (MockSessionsList.SelectedItem is not SessionDisplayItem sel) return;
            _activeSessionId      = sel.OpenCodeSessionId;
            _activeLocalSessionId = Guid.TryParse(sel.Id, out var g) ? g : null;
            JSRaw("window.gasAPI.clearConversation()");

            try
            {
                using var db = new GASDbContext();
                var logs = db.LogEntries
                             .Where(l => l.SessionId == Guid.Parse(sel.Id))
                             .OrderBy(l => l.CreatedAt).ToList();

                AddUserMessage(sel.Intent);

                foreach (var log in logs)
                {
                    if (log.Kind is "text" or "thought")
                        JS("gasAPI.onPartUpdated", new
                        {
                            partID = log.Id.ToString(),
                            type   = log.Kind == "thought" ? "reasoning" : "text",
                            text   = log.RawJson
                        });
                    else if (log.Kind.StartsWith("tool:"))
                    {
                        var p = log.Kind.Split(':');
                        JS("gasAPI.addTool", new
                        {
                            id     = log.Id.ToString(),
                            name   = p.ElementAtOrDefault(1) ?? "Tool",
                            status = p.ElementAtOrDefault(2) ?? "completed",
                            input  = (string?)null,
                            output = log.RawJson
                        });
                    }
                }
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Session load failed: {ex}"); }
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
            SaveLog("user", text);
            (Application.Current as App)?.StartRealAgentRun(text, _activeSessionId);
        }

        // ─────────────────────────────────────────────────────────────
        //  Helpers
        // ─────────────────────────────────────────────────────────────
        private static SolidColorBrush Brush(string hex) =>
            (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;

        private static string? GetStr(JsonElement el, string key) =>
            el.TryGetProperty(key, out var v) ? v.GetString() : null;

        private static string? SafeStr(JsonElement el) =>
            el.ValueKind == JsonValueKind.String ? el.GetString() : el.ToString();

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
