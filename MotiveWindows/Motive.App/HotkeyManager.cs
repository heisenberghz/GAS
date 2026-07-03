using System;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;

namespace Motive.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public class HotkeyManager : IDisposable
    {
        private const int WM_HOTKEY = 0x0312;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [Flags]
        public enum KeyModifiers : uint
        {
            None = 0x0000,
            Alt = 0x0001,
            Control = 0x0002,
            Shift = 0x0004,
            Windows = 0x0008,
            NoRepeat = 0x4000
        }

        private readonly IntPtr _hwnd;
        private readonly HwndSource _hwndSource;
        private readonly int _hotkeyId;
        private bool _isRegistered;

        /// <summary>
        /// Fires when the registered global hotkey is pressed.
        /// </summary>
        public event Action? HotkeyPressed;

        public HotkeyManager(IntPtr hwnd, int hotkeyId = 9000)
        {
            _hwnd = hwnd;
            _hotkeyId = hotkeyId;
            _hwndSource = HwndSource.FromHwnd(_hwnd) ?? throw new InvalidOperationException("Failed to get HwndSource from Hwnd.");
            _hwndSource.AddHook(HwndHook);
        }

        /// <summary>
        /// Registers a global hotkey. Returns true if successful.
        /// </summary>
        public bool Register(KeyModifiers modifiers, Key key)
        {
            if (_isRegistered)
            {
                Unregister();
            }

            uint vk = (uint)KeyInterop.VirtualKeyFromKey(key);
            _isRegistered = RegisterHotKey(_hwnd, _hotkeyId, (uint)modifiers, vk);
            return _isRegistered;
        }

        /// <summary>
        /// Unregisters the global hotkey.
        /// </summary>
        public void Unregister()
        {
            if (_isRegistered)
            {
                UnregisterHotKey(_hwnd, _hotkeyId);
                _isRegistered = false;
            }
        }

        private IntPtr HwndHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY && wParam.ToInt32() == _hotkeyId)
            {
                HotkeyPressed?.Invoke();
                handled = true;
            }
            return IntPtr.Zero;
        }

        public void Dispose()
        {
            Unregister();
            _hwndSource.RemoveHook(HwndHook);
            GC.SuppressFinalize(this);
        }
    }
}
