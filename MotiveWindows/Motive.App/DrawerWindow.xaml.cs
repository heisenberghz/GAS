using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;

namespace Motive.App
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

            LoadMockSessions();
        }

        /// <summary>
        /// Shows the docked drawer window and runs the slide-in animation.
        /// </summary>
        public void ShowDrawer()
        {
            if (_isIntendedVisible) return;
            _isIntendedVisible = true;

            PositionDockedToRight();
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

        /// <summary>
        /// Docks the window to the right-side working area of the monitor containing the cursor.
        /// </summary>
        private void PositionDockedToRight()
        {
            var workArea = GetActiveScreenWorkArea();

            this.Left = workArea.Right - this.Width + 20; // 20px overlap for drop-shadow area
            this.Top = workArea.Top;
            this.Height = workArea.Height;
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

            return new Rect(
                SystemParameters.WorkArea.Left,
                SystemParameters.WorkArea.Top,
                SystemParameters.WorkArea.Width,
                SystemParameters.WorkArea.Height
            );
        }

        private void LoadMockSessions()
        {
            var mocks = new List<MockSession>
            {
                new MockSession { Intent = "Review project and fix git warning", DateStr = "July 3, 11:30 AM", Icon = Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24, IconColor = "#10B981" },
                new MockSession { Intent = "Build local configuration classes", DateStr = "July 2, 8:40 PM", Icon = Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24, IconColor = "#10B981" },
                new MockSession { Intent = "Setup EF Core models and tests", DateStr = "July 2, 3:15 PM", Icon = Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24, IconColor = "#10B981" },
                new MockSession { Intent = "Create initial C# WPF solutions structures", DateStr = "July 1, 9:10 AM", Icon = Wpf.Ui.Controls.SymbolRegular.CheckmarkCircle24, IconColor = "#10B981" }
            };

            MockSessionsList.ItemsSource = mocks;
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
            if (string.IsNullOrEmpty(text)) return;

            // Clear input box
            InputTextBox.Text = string.Empty;

            // In Phase 5A, this is a mock. Just alert.
            MessageBox.Show($"Reply to Agent: \"{text}\"\n(This will send to the real OpenCode server in Phase 5D)", "Motive", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        public class MockSession
        {
            public string Intent { get; set; } = string.Empty;
            public string DateStr { get; set; } = string.Empty;
            public Wpf.Ui.Controls.SymbolRegular Icon { get; set; }
            public string IconColor { get; set; } = "#8A8A8A";
        }
    }
}
