using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
using GAS.Core.Data;
using GAS.Core.Models;

namespace GAS.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class CommandBarWindow : Window
    {
        #region Win32 P/Invokes for Active Monitor Bounds
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
        private System.Collections.Generic.List<string> _history = new System.Collections.Generic.List<string>();
        private int _historyIndex = -1;

        public CommandBarWindow()
        {
            InitializeComponent();
            
            // Apply Mica Backdrop if available via Wpf.Ui
            try
            {
                Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica);
            }
            catch
            {
                // Fallback to custom brush in XAML
            }
        }

        /// <summary>
        /// Updates the workspace breadcrumb and provider chip shown at the bottom of the command bar.
        /// Call this just before ShowCommandBar() so the user always sees current context.
        /// </summary>
        /// <param name="workspacePath">Full path of the detected workspace (e.g. D:\Projects\MyAPI).</param>
        /// <param name="providerName">Friendly name of the active provider/model (e.g. "Claude 3.5 Sonnet").</param>
        public void UpdateContext(string? workspacePath, string? providerName)
        {
            Dispatcher.Invoke(() =>
            {
                // --- Workspace breadcrumb ---
                if (!string.IsNullOrWhiteSpace(workspacePath))
                {
                    var name = System.IO.Path.GetFileName(workspacePath.TrimEnd('\\', '/'));
                    if (string.IsNullOrEmpty(name)) name = workspacePath;
                    WorkspaceNameLabel.Text = name;
                    WorkspacePathLabel.Text = workspacePath;
                }
                else
                {
                    WorkspaceNameLabel.Text = "No workspace";
                    WorkspacePathLabel.Text = string.Empty;
                }

                // --- Provider chip ---
                if (!string.IsNullOrWhiteSpace(providerName))
                {
                    ProviderLabel.Text = providerName;
                    // Color the dot based on the provider family
                    var lower = providerName.ToLowerInvariant();
                    string dotColor;
                    if (lower.Contains("claude") || lower.Contains("anthropic"))
                        dotColor = "#D97706";   // amber — Anthropic
                    else if (lower.Contains("gemini") || lower.Contains("google"))
                        dotColor = "#10B981";   // green — Google
                    else if (lower.Contains("gpt") || lower.Contains("openai"))
                        dotColor = "#3B82F6";   // blue — OpenAI
                    else if (lower.Contains("ollama") || lower.Contains("zen"))
                        dotColor = "#8B5CF6";   // violet — local models
                    else
                        dotColor = "#6366F1";   // indigo — unknown/default
                    ProviderDot.Fill = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter()
                        .ConvertFromString(dotColor)!;
                }
                else
                {
                    ProviderLabel.Text = "No model";
                    ProviderDot.Fill = System.Windows.Media.Brushes.Gray;
                }
            });
        }

        /// <summary>
        /// Shows the Command Bar with a slide and fade transition.
        /// </summary>
        public void ShowCommandBar()
        {
            if (_isIntendedVisible) return;
            _isIntendedVisible = true;

            InputTextBox.Text = string.Empty;
            LoadHistory();

            PositionAtUpperThird();
            this.Show();
            this.Activate();

            var showSb = (Storyboard)Resources["ShowStoryboard"];
            showSb.Begin(this);

            InputTextBox.Focus();
        }

        /// <summary>
        /// Hides the Command Bar with a transition.
        /// </summary>
        public void HideCommandBar()
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

        /// <summary>
        /// Centers the window horizontally and positions it in the upper third of the active screen.
        /// </summary>
        private void PositionAtUpperThird()
        {
            var workArea = GetActiveScreenWorkArea();

            this.Left = workArea.Left + (workArea.Width - this.Width) / 2;
            this.Top = workArea.Top + (workArea.Height * 0.3) - (this.Height / 2);
        }

        /// <summary>
        /// Retrieves the working area bounds of the monitor containing the mouse cursor.
        /// </summary>
        private Rect GetActiveScreenWorkArea()
        {
            var pt = new POINT();
            GetCursorPos(out pt);
            IntPtr hMonitor = MonitorFromPoint(pt, 1 /* MONITOR_DEFAULTTONEAREST */);

            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(mi);
            if (GetMonitorInfo(hMonitor, ref mi))
            {
                // Convert native pixels to WPF device-independent units
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

            // Standard fallback to primary screen working area
            return new Rect(
                SystemParameters.WorkArea.Left,
                SystemParameters.WorkArea.Top,
                SystemParameters.WorkArea.Width,
                SystemParameters.WorkArea.Height
            );
        }

        private void Window_Deactivated(object sender, EventArgs e)
        {
            // Auto hide command bar when focus is lost
            HideCommandBar();
        }

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape)
            {
                HideCommandBar();
                e.Handled = true;
            }
            else if (e.Key == Key.Enter)
            {
                SubmitPrompt();
                e.Handled = true;
            }
        }

        private void InputTextBox_GotFocus(object sender, RoutedEventArgs e)
        {
            // Ensure textbox is fully selected/ready
            InputTextBox.SelectAll();
        }

        private void SubmitPrompt()
        {
            var text = InputTextBox.Text.Trim();
            if (string.IsNullOrEmpty(text)) return;

            HideCommandBar();

            if (Application.Current is App app)
            {
                app.StartRealAgentRun(text);
            }
        }

        private void LoadHistory()
        {
            try
            {
                using var db = new GASDbContext();
                // Load last 50 intents ordered by created time descending
                var items = System.Linq.Enumerable.ToList(
                    System.Linq.Enumerable.Select(
                        System.Linq.Queryable.Take(
                            System.Linq.Queryable.OrderByDescending(db.Sessions, s => s.CreatedAt),
                            50
                        ),
                        s => s.Intent
                    )
                );

                _history.Clear();
                foreach (var item in items)
                {
                    if (!string.IsNullOrEmpty(item) && !_history.Contains(item))
                    {
                        _history.Add(item);
                    }
                }
                _historyIndex = -1;
            }
            catch
            {
                // Ignore DB errors during history loading
            }
        }

        private void InputTextBox_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Up)
            {
                if (_history.Count > 0)
                {
                    if (_historyIndex < _history.Count - 1)
                    {
                        _historyIndex++;
                        InputTextBox.Text = _history[_historyIndex];
                        InputTextBox.CaretIndex = InputTextBox.Text.Length;
                    }
                    e.Handled = true;
                }
            }
            else if (e.Key == Key.Down)
            {
                if (_history.Count > 0)
                {
                    if (_historyIndex > 0)
                    {
                        _historyIndex--;
                        InputTextBox.Text = _history[_historyIndex];
                        InputTextBox.CaretIndex = InputTextBox.Text.Length;
                    }
                    else if (_historyIndex == 0)
                    {
                        _historyIndex = -1;
                        InputTextBox.Text = string.Empty;
                    }
                    e.Handled = true;
                }
            }
        }
    }
}

