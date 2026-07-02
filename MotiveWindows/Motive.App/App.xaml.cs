using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using Hardcodet.Wpf.TaskbarNotification;
using Motive.Core;
using Motive.Core.Data;

namespace Motive.App
{
    public partial class App : Application
    {
        private static Mutex? _mutex;
        private TaskbarIcon? _notifyIcon;
        private OpenCodeServer? _openCodeServer;
        private CredentialStore? _credentialStore;

        private MenuItem? _statusHeaderItem;
        private System.Drawing.Icon? _iconIdle;
        private System.Drawing.Icon? _iconThinking;
        private System.Drawing.Icon? _iconExecuting;
        private System.Drawing.Icon? _iconError;

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            try
            {
                // 1. Single Instance Check via Mutex
                const string appGuid = "Global\\MotiveWindowsBackgroundAppMutexGuid";
                _mutex = new Mutex(true, appGuid, out bool isNewInstance);
                if (!isNewInstance)
                {
                    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup.log"), "Motive is already running. Exiting.");
                    Shutdown();
                    return;
                }

                // 2. Initialize Database & Secure Storage
                using (var db = new MotiveDbContext())
                {
                    db.Database.EnsureCreated();
                }
                _credentialStore = new CredentialStore();

                // 3. Initialize background server
                _openCodeServer = new OpenCodeServer();
                _openCodeServer.ServerUrlDetected += OnServerUrlDetected;
                _openCodeServer.ProcessExited += OnServerProcessExited;

                // Start server in the background (using Resolved binary)
                Task.Run(async () =>
                {
                    try
                    {
                        var binaryManager = new BinaryManager();
                        var (binaryPath, error) = binaryManager.ResolveBinary();
                        if (binaryPath != null)
                        {
                            var workingDir = AppDomain.CurrentDomain.BaseDirectory;
                            await _openCodeServer.StartAsync(binaryPath, workingDir);
                        }
                    }
                    catch (Exception ex)
                    {
                        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "engine-startup-crash.log"), ex.ToString());
                        Dispatcher.Invoke(() => SetAppState(AppStateIcon.Error, "Engine Startup Failed"));
                    }
                });

                // 4. Create Tray Icon
                InitializeTrayIcon();
                File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup.log"), "Motive started successfully in tray.");
            }
            catch (Exception ex)
            {
                File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "crash.log"), ex.ToString());
                Shutdown();
            }
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void InitializeTrayIcon()
        {
            // Pre-compile dynamic status icons
            _iconIdle = CreateDynamicIcon(System.Drawing.Color.FromArgb(99, 102, 241));      // Indigo
            _iconThinking = CreateDynamicIcon(System.Drawing.Color.FromArgb(245, 158, 11));  // Amber
            _iconExecuting = CreateDynamicIcon(System.Drawing.Color.FromArgb(16, 185, 129)); // Emerald
            _iconError = CreateDynamicIcon(System.Drawing.Color.FromArgb(239, 68, 68));      // Rose

            // Create NotifyIcon Context Menu
            var contextMenu = new ContextMenu();

            _statusHeaderItem = new MenuItem
            {
                Header = "Motive: Idle",
                IsEnabled = false,
                FontWeight = FontWeights.Bold
            };
            contextMenu.Items.Add(_statusHeaderItem);
            contextMenu.Items.Add(new Separator());

            var commandBarItem = new MenuItem { Header = "Toggle Command Bar (Alt+Space)" };
            commandBarItem.Click += (s, e) => ToggleCommandBar();
            contextMenu.Items.Add(commandBarItem);

            var settingsItem = new MenuItem { Header = "Settings..." };
            settingsItem.Click += (s, e) => ShowSettings();
            contextMenu.Items.Add(settingsItem);

            contextMenu.Items.Add(new Separator());

            var quitItem = new MenuItem { Header = "Quit" };
            quitItem.Click += (s, e) => ShutdownApp();
            contextMenu.Items.Add(quitItem);

            // Initialize NotifyIcon
            _notifyIcon = new TaskbarIcon
            {
                Icon = _iconIdle,
                ToolTipText = "Motive Background Agent",
                ContextMenu = contextMenu
            };

            // Left click behavior: toggles the drawer
            _notifyIcon.TrayLeftMouseDown += (s, e) => ToggleDrawer();
        }

        private void ToggleDrawer()
        {
            // Will be wired to Phase 5 DrawerWindow
            MessageBox.Show("Toggle Drawer Panel (Coming in Phase 5)", "Motive", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void ToggleCommandBar()
        {
            // Will be wired to Phase 4 CommandBarWindow
            MessageBox.Show("Toggle Command Bar (Coming in Phase 4)", "Motive", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void ShowSettings()
        {
            // Will be wired to Phase 5 SettingsWindow
            MessageBox.Show("Show Settings Dialog (Coming in Phase 5)", "Motive", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void OnServerUrlDetected(string url)
        {
            Dispatcher.Invoke(() => SetAppState(AppStateIcon.Executing, "Server Connected"));
            // Auto revert to idle after 2 seconds of connection success
            Task.Run(async () =>
            {
                await Task.Delay(2000);
                Dispatcher.Invoke(() => SetAppState(AppStateIcon.Idle, "Idle"));
            });
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void OnServerProcessExited(int exitCode)
        {
            Dispatcher.Invoke(() => SetAppState(AppStateIcon.Error, $"Engine Stopped ({exitCode})"));
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void SetAppState(AppStateIcon state, string statusText)
        {
            if (_notifyIcon == null || _statusHeaderItem == null) return;

            _statusHeaderItem.Header = $"Motive: {statusText}";
            _notifyIcon.ToolTipText = $"Motive: {statusText}";

            switch (state)
            {
                case AppStateIcon.Idle:
                    _notifyIcon.Icon = _iconIdle;
                    break;
                case AppStateIcon.Thinking:
                    _notifyIcon.Icon = _iconThinking;
                    break;
                case AppStateIcon.Executing:
                    _notifyIcon.Icon = _iconExecuting;
                    break;
                case AppStateIcon.Error:
                    _notifyIcon.Icon = _iconError;
                    break;
            }
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private System.Drawing.Icon CreateDynamicIcon(System.Drawing.Color circleColor)
        {
            using (var bmp = new System.Drawing.Bitmap(32, 32))
            {
                using (var g = System.Drawing.Graphics.FromImage(bmp))
                {
                    g.Clear(System.Drawing.Color.Transparent);
                    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

                    using (var brush = new System.Drawing.SolidBrush(circleColor))
                    {
                        g.FillEllipse(brush, 2, 2, 28, 28);
                    }

                    using (var pen = new System.Drawing.Pen(System.Drawing.Color.White, 3))
                    {
                        // Draw a simple letter M in white
                        g.DrawLine(pen, 8, 22, 8, 10);
                        g.DrawLine(pen, 8, 10, 16, 17);
                        g.DrawLine(pen, 16, 17, 24, 10);
                        g.DrawLine(pen, 24, 10, 24, 22);
                    }
                }
                return System.Drawing.Icon.FromHandle(bmp.GetHicon());
            }
        }

        private void ShutdownApp()
        {
            _openCodeServer?.Dispose();
            _notifyIcon?.Dispose();
            
            _iconIdle?.Dispose();
            _iconThinking?.Dispose();
            _iconExecuting?.Dispose();
            _iconError?.Dispose();

            _mutex?.ReleaseMutex();
            _mutex?.Dispose();

            Shutdown();
        }

        protected override void OnExit(ExitEventArgs e)
        {
            ShutdownApp();
            base.OnExit(e);
        }

        private enum AppStateIcon
        {
            Idle,
            Thinking,
            Executing,
            Error
        }
    }
}
