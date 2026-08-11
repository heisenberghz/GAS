using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using System.Text.Json;
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
        //  State & Engine
        // ─────────────────────────────────────────────────────────────
        private bool _isIntendedVisible;
        private string? _activeSessionId;
        private Guid? _activeLocalSessionId;

        private readonly ConversationState _conversationState = new();

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

            WireConversationStateEvents();
            InitWebView();
            LoadSessionHistory();
        }

        // ─────────────────────────────────────────────────────────────
        //  ConversationState Event Handlers → Presenter
        // ─────────────────────────────────────────────────────────────
        private void WireConversationStateEvents()
        {
            _conversationState.OnConversationCleared += () =>
            {
                JSRaw("window.gasAPI.clearConversation()");
                Dispatcher.Invoke(() => TokenCostPill.Visibility = Visibility.Collapsed);
            };

            _conversationState.OnUserTurnAdded += (userTurn) =>
            {
                JS("gasAPI.addUserTurn", userTurn);
            };

            _conversationState.OnAgentTurnStarted += () =>
            {
                JSRaw("window.gasAPI.startAgentTurn()");
            };

            _conversationState.OnTextPartUpdated += (textPart) =>
            {
                JS("gasAPI.updateTextPart", textPart);
                if (textPart.IsFinalized)
                {
                    SaveLog(textPart.IsReasoning ? "thought" : "text", textPart.FullText);
                }
            };

            _conversationState.OnToolPartUpdated += (toolPart) =>
            {
                JS("gasAPI.updateToolPart", toolPart);
                SaveLog($"tool:{toolPart.ToolName}:{toolPart.Status}", toolPart.FormattedOutput);
            };

            _conversationState.OnTokenUsageUpdated += (tokenUsage) =>
            {
                Dispatcher.Invoke(() =>
                {
                    TokenCostPill.Visibility = Visibility.Visible;
                    TokenCountLabel.Text = tokenUsage.TotalTokens >= 1000
                        ? $"{tokenUsage.TotalTokens / 1000.0:F1}k tok"
                        : $"{tokenUsage.TotalTokens} tok";
                    CostLabel.Text = $"${tokenUsage.EstimatedCostUsd:F4}";
                });
            };
        }

        // ─────────────────────────────────────────────────────────────
        //  WebView2 initialization
        // ─────────────────────────────────────────────────────────────
        private async void InitWebView()
        {
            try
            {
                var dataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "GAS", "WebView2");

                var env = await CoreWebView2Environment.CreateAsync(userDataFolder: dataFolder);

                await ConversationView.EnsureCoreWebView2Async(env);

                ConversationView.DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 12, 12, 15);
                ConversationView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                ConversationView.CoreWebView2.Settings.IsStatusBarEnabled = false;
                ConversationView.CoreWebView2.Settings.AreDevToolsEnabled = false;

                ConversationView.CoreWebView2.NavigateToString(ConversationHtml.GetHtml());
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"WebView2 init failed: {ex.Message}");
            }
        }

        private void ConversationView_NavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            _webViewReady = true;
            while (_scriptQueue.Count > 0)
                _ = ConversationView.CoreWebView2.ExecuteScriptAsync(_scriptQueue.Dequeue());
        }

        // ─────────────────────────────────────────────────────────────
        //  JS Bridge (ExecuteScriptAsync safely)
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
        //  Session Lifecycle
        // ─────────────────────────────────────────────────────────────
        public void OnNewSessionStarted(string sessionId, Guid localSessionId, string prompt)
        {
            _activeSessionId      = sessionId;
            _activeLocalSessionId = localSessionId;

            _conversationState.Clear();
            StartElapsedTimer();
            UpdateStatusStrip("Thinking", _currentModel, _currentWorkspace, null);
            _conversationState.AddUserTurn(prompt);
            LoadSessionHistory();
        }

        public void OnSessionResumed(string sessionId, Guid localSessionId)
        {
            _activeSessionId      = sessionId;
            _activeLocalSessionId = localSessionId;
            _conversationState.Clear();

            try
            {
                using var db = new GASDbContext();
                var session = db.Sessions.Find(localSessionId);
                if (session == null) return;

                _conversationState.AddUserTurn(session.Intent, session.CreatedAt.ToLocalTime().ToString("h:mm tt"));

                var logs = db.LogEntries
                             .Where(l => l.SessionId == session.Id)
                             .OrderBy(l => l.CreatedAt)
                             .ToList();

                foreach (var log in logs)
                {
                    if (log.Kind is "text" or "thought")
                    {
                        var isReasoning = log.Kind == "thought";
                        _conversationState.ProcessEvent(new OpenCodeEvent
                        {
                            type = "message.part.updated",
                            properties = JsonSerializer.SerializeToElement(new
                            {
                                part = new
                                {
                                    id = log.Id.ToString(),
                                    type = isReasoning ? "reasoning" : "text",
                                    text = log.RawJson
                                }
                            })
                        });
                    }
                    else if (log.Kind.StartsWith("tool:"))
                    {
                        var parts = log.Kind.Split(':');
                        var toolName = parts.ElementAtOrDefault(1) ?? "Tool";
                        var status   = parts.ElementAtOrDefault(2) ?? "completed";

                        var normalized = ConversationState.NormalizeToolPart(
                            log.Id.ToString(), toolName, status, null, log.RawJson);

                        JS("gasAPI.updateToolPart", normalized);
                    }
                }
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Resume failed: {ex}"); }

            LoadSessionHistory();
        }

        // ─────────────────────────────────────────────────────────────
        //  Event Dispatch from OpenCode
        // ─────────────────────────────────────────────────────────────
        public void HandleIncomingEvent(OpenCodeEvent ev)
        {
            if (string.IsNullOrEmpty(_activeSessionId)) return;
            _conversationState.ProcessEvent(ev);
        }

        // ─────────────────────────────────────────────────────────────
        //  Status Strip
        // ─────────────────────────────────────────────────────────────
        public void UpdateStatusStrip(string? state, string? model, string? workspace, TimeSpan? elapsed)
        {
            Dispatcher.Invoke(() =>
            {
                if (!string.IsNullOrEmpty(model))     _currentModel     = model;
                if (!string.IsNullOrEmpty(workspace)) _currentWorkspace = workspace;

                if (!string.IsNullOrEmpty(state))
                {
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

                    if (!running)
                    {
                        _elapsedTimer?.Stop();
                        ElapsedLabel.Visibility = Visibility.Collapsed;
                    }
                }

                StatusModelLabel.Text     = _currentModel;
                var projectName = WorkspaceDetector.DeriveProjectName(_currentWorkspace);
                WorkspaceNameText.Text    = string.IsNullOrEmpty(projectName) ? "GAS" : projectName;
                StatusWorkspaceLabel.Text = string.IsNullOrEmpty(projectName) ? _currentWorkspace : projectName;
                WorkspacePathText.Text    = _currentWorkspace;

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
                ConnectionDot.Fill = connected ? Brush("#10B981") : Brush("#F59E0B");
                if (connected && !string.IsNullOrEmpty(workspacePath))
                {
                    _currentWorkspace = workspacePath;
                    var projectName = WorkspaceDetector.DeriveProjectName(workspacePath);
                    WorkspaceNameText.Text = string.IsNullOrEmpty(projectName) ? "GAS" : projectName;
                    WorkspacePathText.Text = workspacePath;
                    StatusWorkspaceLabel.Text = string.IsNullOrEmpty(projectName) ? workspacePath : projectName;
                }
                else
                {
                    WorkspacePathText.Text = "Reconnecting…";
                }
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
        //  Session History Sidebar
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
                        Id                = s.Id.ToString(),
                        OpenCodeSessionId = s.OpenCodeSessionId,
                        Intent            = s.Intent,
                        DateStr           = s.CreatedAt.ToLocalTime().ToString("MMM dd, h:mm tt"),
                        Icon              = s.Status == SessionStatus.Completed
                                                ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24
                                                : Wpf.Ui.Controls.SymbolRegular.Record24,
                        IconColor         = s.Status == SessionStatus.Completed ? "#10B981" : "#64748B"
                    }).ToList();
                });
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"History load failed: {ex.Message}"); }
        }

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
        //  UI Event Handlers
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
            _conversationState.Clear();
        }

        private bool _isHistoryOpen = false;

        private void ToggleHistoryButton_Click(object sender, RoutedEventArgs e)
        {
            _isHistoryOpen = !_isHistoryOpen;
            if (_isHistoryOpen)
            {
                HistoryColumn.Width       = new GridLength(220);
                SplitterColumn.Width      = GridLength.Auto;
                HistoryPanel.Visibility    = Visibility.Visible;
                SidebarSplitter.Visibility = Visibility.Visible;
                UpdateWindowWidth(700);
            }
            else
            {
                HistoryColumn.Width       = new GridLength(0);
                SplitterColumn.Width      = new GridLength(0);
                HistoryPanel.Visibility    = Visibility.Collapsed;
                SidebarSplitter.Visibility = Visibility.Collapsed;
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
                        Id                = s.Id.ToString(),
                        OpenCodeSessionId = s.OpenCodeSessionId,
                        Intent            = s.Intent,
                        DateStr           = s.CreatedAt.ToString("MMM dd, h:mm tt"),
                        Icon              = s.Status == SessionStatus.Completed
                                                ? Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24
                                                : Wpf.Ui.Controls.SymbolRegular.Record24,
                        IconColor         = s.Status == SessionStatus.Completed ? "#10B981" : "#64748B"
                    }).ToList();
            }
            catch { }
        }

        private void SessionsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (MockSessionsList.SelectedItem is not SessionDisplayItem sel) return;
            _activeSessionId      = sel.OpenCodeSessionId;
            _activeLocalSessionId = Guid.TryParse(sel.Id, out var g) ? g : null;
            _conversationState.Clear();

            try
            {
                using var db = new GASDbContext();
                var logs = db.LogEntries
                             .Where(l => l.SessionId == Guid.Parse(sel.Id))
                             .OrderBy(l => l.CreatedAt).ToList();

                _conversationState.AddUserTurn(sel.Intent);

                foreach (var log in logs)
                {
                    if (log.Kind is "text" or "thought")
                    {
                        var isReasoning = log.Kind == "thought";
                        _conversationState.ProcessEvent(new OpenCodeEvent
                        {
                            type = "message.part.updated",
                            properties = JsonSerializer.SerializeToElement(new
                            {
                                part = new
                                {
                                    id = log.Id.ToString(),
                                    type = isReasoning ? "reasoning" : "text",
                                    text = log.RawJson
                                }
                            })
                        });
                    }
                    else if (log.Kind.StartsWith("tool:"))
                    {
                        var parts = log.Kind.Split(':');
                        var toolName = parts.ElementAtOrDefault(1) ?? "Tool";
                        var status   = parts.ElementAtOrDefault(2) ?? "completed";

                        var normalized = ConversationState.NormalizeToolPart(
                            log.Id.ToString(), toolName, status, null, log.RawJson);

                        JS("gasAPI.updateToolPart", normalized);
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
            _conversationState.AddUserTurn(text);
            SaveLog("user", text);
            (Application.Current as App)?.StartRealAgentRun(text, _activeSessionId);
        }

        private static SolidColorBrush Brush(string hex) =>
            (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;

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
