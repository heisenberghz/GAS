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
        /// Shows the Command Bar with a slide and fade transition.
        /// </summary>
        public void ShowCommandBar()
        {
            if (_isIntendedVisible) return;
            _isIntendedVisible = true;

            InputTextBox.Text = string.Empty;

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
    }
}

