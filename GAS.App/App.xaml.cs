using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using Hardcodet.Wpf.TaskbarNotification;
using System.Text.Json;
using GAS.Core;
using GAS.Core.Data;
using GAS.Core.Models;

namespace GAS.App
{
    public partial class App : Application
    {
        private static Mutex? _mutex;
        private TaskbarIcon? _notifyIcon;
        private OpenCodeServer? _openCodeServer;
        private OpenCodeClient? _openCodeClient;
        private CredentialStore? _credentialStore;
        private CommandBarWindow? _commandBar;
        private DrawerWindow? _drawer;
        private HotkeyManager? _hotkeyManager;
        private MenuItem? _commandBarMenuItem;

        private MenuItem? _statusHeaderItem;
        private System.Drawing.Icon? _iconIdle;
        private System.Drawing.Icon? _iconThinking;
        private System.Drawing.Icon? _iconExecuting;
        private System.Drawing.Icon? _iconError;
        private System.Drawing.Icon? _iconWaitingForApproval;

        // Fix 1.1 / Phase 2: workspace path resolved dynamically via WorkspaceDetector
        private string _workspacePath = string.Empty;
        // Fix 1.2: track restart attempts to avoid infinite crash loop
        private int _serverRestartAttempts = 0;
        // Fix 1.3: track the active session ID to mark it Completed
        private string? _activeSessionId;

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            try
            {
                // 1. Single Instance Check via Mutex
                const string appGuid = "Global\\GASWindowsBackgroundAppMutexGuid";
                _mutex = new Mutex(true, appGuid, out bool isNewInstance);
                if (!isNewInstance)
                {
                    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup.log"), "GAS is already running. Exiting.");
                    Shutdown();
                    return;
                }

                // 2. Initialize Database & Secure Storage
                using (var db = new GASDbContext())
                {
                    db.Database.EnsureCreated();
                }
                _credentialStore = new CredentialStore();

                // Check if API keys are configured, otherwise trigger onboarding
                var openAiKey = _credentialStore.Read("OpenAiApiKey");
                var anthropicKey = _credentialStore.Read("AnthropicApiKey");

                if (string.IsNullOrEmpty(openAiKey) && string.IsNullOrEmpty(anthropicKey))
                {
                    var onboarding = new OnboardingWindow();
                    onboarding.ShowDialog();

                    if (!onboarding.IsOnboardingSuccess)
                    {
                        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup.log"), "Onboarding cancelled. Exiting.");
                        Shutdown();
                        return;
                    }
                }

                // Initialize Command Bar, Drawer, and Hotkey Hook
                _commandBar = new CommandBarWindow();
                var helper = new System.Windows.Interop.WindowInteropHelper(_commandBar);
                helper.EnsureHandle(); // Ensure HWND exists before registering hotkey

                _drawer = new DrawerWindow();
                var drawerHelper = new System.Windows.Interop.WindowInteropHelper(_drawer);
                drawerHelper.EnsureHandle(); // Ensure HWND exists

                _hotkeyManager = new HotkeyManager(helper.Handle);
                _hotkeyManager.HotkeyPressed += OnHotkeyPressed;

                // Load Settings and Register hotkey from configuration
                var settings = SettingsManager.Load();
                RegisterHotkeyFromSettings(settings);

                // 3. Initialize background server
                _openCodeServer = new OpenCodeServer();
                _openCodeServer.ServerUrlDetected += OnServerUrlDetected;
                _openCodeServer.ProcessExited += OnServerProcessExited;

                var binaryManager = new BinaryManager();
                var (binaryPath, error) = binaryManager.ResolveBinary();

                if (binaryPath == null)
                {
                    // Open the downloader window on the UI thread
                    var downloader = new DownloaderWindow();
                    var downloadResult = downloader.ShowDialog();
                    
                    if (downloadResult == true && downloader.IsDownloadSuccess)
                    {
                        // Try resolving again
                        (binaryPath, error) = binaryManager.ResolveBinary();
                    }
                }

                if (binaryPath == null)
                {
                    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup.log"), "Engine binary not found or downloaded. Exiting.");
                    Shutdown();
                    return;
                }

                // Start server in the background (using Resolved binary)
                var resolvedPath = binaryPath;
                Task.Run(async () =>
                {
                    try
                    {
                        var env = new System.Collections.Generic.Dictionary<string, string>();
                        var openAi = _credentialStore.Read("OpenAiApiKey");
                        var anthropic = _credentialStore.Read("AnthropicApiKey");
                        var gemini = _credentialStore.Read("GeminiApiKey");
                        var openRouter = _credentialStore.Read("OpenRouterApiKey");
                        var zen = _credentialStore.Read("ZenApiKey");
                        var ollama = _credentialStore.Read("OllamaEndpoint");

                        if (!string.IsNullOrEmpty(openAi)) env["OPENAI_API_KEY"] = openAi;
                        if (!string.IsNullOrEmpty(anthropic)) env["ANTHROPIC_API_KEY"] = anthropic;
                        if (!string.IsNullOrEmpty(gemini)) env["GEMINI_API_KEY"] = gemini;
                        if (!string.IsNullOrEmpty(openRouter)) env["OPENROUTER_API_KEY"] = openRouter;
                        if (!string.IsNullOrEmpty(zen)) env["ZEN_API_KEY"] = zen;
                        if (!string.IsNullOrEmpty(ollama)) env["OLLAMA_HOST"] = ollama;

                        var workingDir = AppDomain.CurrentDomain.BaseDirectory;
                        await _openCodeServer.StartAsync(resolvedPath, workingDir, env);
                    }
                    catch (Exception ex)
                    {
                        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "engine-startup-crash.log"), ex.ToString());
                        Dispatcher.Invoke(() => SetAppState(AppStateIcon.Error, "Engine Startup Failed"));
                    }
                });

                // 4. Create Tray Icon
                InitializeTrayIcon();
                File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup.log"), "GAS started successfully in tray.");
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
            _iconWaitingForApproval = CreateDynamicIcon(System.Drawing.Color.FromArgb(168, 85, 247)); // Purple (waiting approval)

            // Create NotifyIcon Context Menu
            var contextMenu = new ContextMenu();

            _statusHeaderItem = new MenuItem
            {
                Header = "GAS: Idle",
                IsEnabled = false,
                FontWeight = FontWeights.Bold
            };
            contextMenu.Items.Add(_statusHeaderItem);
            contextMenu.Items.Add(new Separator());

            var settings = SettingsManager.Load();
            var display = GetHotkeyDisplayString(settings);
            _commandBarMenuItem = new MenuItem { Header = $"Toggle Command Bar ({display})" };
            _commandBarMenuItem.Click += (s, e) => ToggleCommandBar();
            contextMenu.Items.Add(_commandBarMenuItem);

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
                ToolTipText = "GAS Background Agent",
                ContextMenu = contextMenu
            };

            // Left click behavior: toggles the drawer
            _notifyIcon.TrayLeftMouseDown += (s, e) => ToggleDrawer();

            // Balloon click behavior: opens/shows the activity drawer
            _notifyIcon.TrayBalloonTipClicked += (s, e) =>
            {
                Dispatcher.Invoke(() =>
                {
                    if (_drawer != null && !_drawer.IsVisible)
                    {
                        _drawer.ShowDrawer();
                    }
                });
            };
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void ToggleDrawer()
        {
            if (_drawer == null) return;
            if (_drawer.IsVisible)
            {
                _drawer.HideDrawer();
            }
            else
            {
                _drawer.ShowDrawer();
            }
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void ToggleCommandBar()
        {
            OnHotkeyPressed();
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void OnHotkeyPressed()
        {
            if (_commandBar == null) return;
            if (_commandBar.IsVisible)
            {
                _commandBar.HideCommandBar();
            }
            else
            {
                _commandBar.ShowCommandBar();
            }
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        public void StartRealAgentRun(string prompt)
        {
            if (_openCodeClient == null)
            {
                MessageBox.Show("OpenCode server is not connected yet. Please try again in a few seconds.", "GAS", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            SetAppState(AppStateIcon.Thinking, "Thinking...");

            System.Threading.Tasks.Task.Run(async () =>
            {
                try
                {
                    // Resolve workspace: saved setting → VS Code → Visual Studio → home dir
                    var settings = SettingsManager.Load();
                    _workspacePath = WorkspaceDetector.Detect(settings.LastWorkspacePath);

                    // Persist the detected path so it becomes the default next time
                    if (settings.LastWorkspacePath != _workspacePath)
                    {
                        settings.LastWorkspacePath = _workspacePath;
                        SettingsManager.Save(settings);
                    }

                    // 1. Create session on OpenCode server
                    var sessionInfo = await _openCodeClient.CreateSessionAsync(prompt);
                    
                    // 2. Insert into SQLite DB
                    using (var db = new GASDbContext())
                    {
                        var newSession = new Session
                        {
                            Id = Guid.Parse(sessionInfo.id),
                            Intent = prompt,
                            Status = SessionStatus.Running,
                            ProjectPath = _workspacePath
                        };
                        db.Sessions.Add(newSession);
                        await db.SaveChangesAsync();
                    }

                    // 3. Update Drawer UI and track active session
                    _activeSessionId = sessionInfo.id;
                    Dispatcher.Invoke(() =>
                    {
                        _drawer?.OnNewSessionStarted(sessionInfo.id, prompt);
                    });

                    // 4. Send the prompt to the background engine
                    await _openCodeClient.SendPromptAsync(sessionInfo.id, prompt, _workspacePath);
                }
                catch (Exception ex)
                {
                    Dispatcher.Invoke(() =>
                    {
                        SetAppState(AppStateIcon.Error, "Error");
                        MessageBox.Show($"Failed to execute agent prompt: {ex.Message}", "GAS", MessageBoxButton.OK, MessageBoxImage.Error);
                    });
                }
            });
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void ShowSettings()
        {
            var settingsWin = new SettingsWindow();
            settingsWin.ShowDialog();
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        public void RebindHotkey(AppSettings settings)
        {
            _hotkeyManager?.Unregister();
            RegisterHotkeyFromSettings(settings);

            if (_commandBarMenuItem != null)
            {
                var display = GetHotkeyDisplayString(settings);
                _commandBarMenuItem.Header = $"Toggle Command Bar ({display})";
            }
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void RegisterHotkeyFromSettings(AppSettings settings)
        {
            if (_hotkeyManager == null) return;

            var modifiers = HotkeyManager.KeyModifiers.None;
            if (settings.CtrlModifier) modifiers |= HotkeyManager.KeyModifiers.Control;
            if (settings.ShiftModifier) modifiers |= HotkeyManager.KeyModifiers.Shift;
            if (settings.AltModifier) modifiers |= HotkeyManager.KeyModifiers.Alt;

            if (Enum.TryParse<System.Windows.Input.Key>(settings.HotkeyKey, out var key))
            {
                var isRegistered = _hotkeyManager.Register(modifiers, key);
                if (!isRegistered)
                {
                    var display = GetHotkeyDisplayString(settings);
                    MessageBox.Show(
                        $"Could not register global hotkey {display}. Another application might be using it.",
                        "GAS - Hotkey Warning",
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning
                    );
                }
            }
        }

        private string GetHotkeyDisplayString(AppSettings settings)
        {
            var parts = new System.Collections.Generic.List<string>();
            if (settings.CtrlModifier) parts.Add("Ctrl");
            if (settings.ShiftModifier) parts.Add("Shift");
            if (settings.AltModifier) parts.Add("Alt");
            parts.Add(settings.HotkeyKey);
            return string.Join("+", parts);
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void OnServerUrlDetected(string url)
        {
            Dispatcher.Invoke(() => SetAppState(AppStateIcon.Executing, "Server Connected"));

            // Initialize OpenCodeClient and start streaming events
            _openCodeClient = new OpenCodeClient(url);
            _openCodeClient.EventReceived += OnOpenCodeEventReceived;
            _openCodeClient.StartStreaming(_workspacePath);

            // Auto revert to idle after 2 seconds of connection success
            Task.Run(async () =>
            {
                await Task.Delay(2000);
                Dispatcher.Invoke(() => SetAppState(AppStateIcon.Idle, "Idle"));
            });
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void OnOpenCodeEventReceived(OpenCodeEvent ev)
        {
            // Route events to Drawer Window
            Dispatcher.Invoke(() =>
            {
                _drawer?.HandleIncomingEvent(ev);
            });

            // Update app states based on status/idle events
            if (ev.type == "session.status")
            {
                if (ev.properties.TryGetProperty("status", out var statusProp))
                {
                    if (statusProp.TryGetProperty("type", out var typeProp))
                    {
                        var statusType = typeProp.GetString();
                        if (statusType == "running")
                        {
                            Dispatcher.Invoke(() => SetAppState(AppStateIcon.Executing, "Executing..."));
                        }
                        else if (statusType == "thinking")
                        {
                            Dispatcher.Invoke(() => SetAppState(AppStateIcon.Thinking, "Thinking..."));
                        }
                    }
                }
            }
            else if (ev.type == "session.idle")
            {
                Dispatcher.Invoke(() => SetAppState(AppStateIcon.Idle, "Idle"));
                // Fix 1.3: mark the active session as Completed in the DB
                if (!string.IsNullOrEmpty(_activeSessionId))
                {
                    var completedId = _activeSessionId;
                    Task.Run(async () =>
                    {
                        try
                        {
                            using var db = new GASDbContext();
                            var session = await db.Sessions.FindAsync(Guid.Parse(completedId));
                            if (session != null)
                            {
                                session.Status = SessionStatus.Completed;
                                await db.SaveChangesAsync();

                                // Notify user of task completion
                                Dispatcher.Invoke(() =>
                                {
                                    _notifyIcon?.ShowBalloonTip(
                                        "Task Completed",
                                        $"The agent has successfully finished the task:\n\"{session.Intent}\"",
                                        BalloonIcon.Info
                                    );
                                });
                            }
                        }
                        catch { /* Non-critical – ignore DB errors here */ }
                    });
                }
            }
            else if (ev.type == "session.error")
            {
                Dispatcher.Invoke(() =>
                {
                    SetAppState(AppStateIcon.Error, "Error");
                    _notifyIcon?.ShowBalloonTip(
                        "Task Failed",
                        "An error occurred during task execution. Click to open logs.",
                        BalloonIcon.Error
                    );
                });
            }
            else if (ev.type == "permission.asked")
            {
                string? requestId = null;
                string permissionType = "Action Authorization";
                string detail = "The agent is waiting for your approval.";

                if (ev.properties.TryGetProperty("id", out var idProp))
                {
                    requestId = idProp.GetString();
                }
                else if (ev.properties.TryGetProperty("requestId", out var reqIdProp))
                {
                    requestId = reqIdProp.GetString();
                }

                if (string.IsNullOrEmpty(requestId)) return;

                if (ev.properties.TryGetProperty("permission", out var permProp))
                {
                    permissionType = permProp.GetString() ?? permissionType;
                }

                if (ev.properties.TryGetProperty("tool", out var toolObjProp))
                {
                    if (toolObjProp.TryGetProperty("name", out var tName))
                    {
                        permissionType = $"{tName.GetString()} Command";
                    }
                    if (toolObjProp.TryGetProperty("arguments", out var tArgs))
                    {
                        detail = tArgs.ValueKind == JsonValueKind.String ? tArgs.GetString() : tArgs.ToString();
                    }
                }
                else if (ev.properties.TryGetProperty("detail", out var detailProp))
                {
                    detail = detailProp.GetString() ?? detail;
                }
                else if (ev.properties.TryGetProperty("pattern", out var patProp))
                {
                    detail = patProp.GetString() ?? detail;
                }

                var settings = SettingsManager.Load();
                var trustMode = settings.TrustMode ?? "Careful";

                if (trustMode == "YOLO")
                {
                    // Auto-approve in YOLO mode
                    Task.Run(async () =>
                    {
                        try
                        {
                            await _openCodeClient!.SendPermissionReplyAsync(requestId, "allow");
                        }
                        catch { }
                    });
                }
                else if (trustMode == "Balanced" && (permissionType.ToLower().Contains("read") || permissionType.ToLower().Contains("view") || permissionType.ToLower().Contains("search")))
                {
                    // Auto-approve safe read actions in Balanced mode
                    Task.Run(async () =>
                    {
                        try
                        {
                            await _openCodeClient!.SendPermissionReplyAsync(requestId, "allow");
                        }
                        catch { }
                    });
                }
                else
                {
                    // Prompt the user via the custom ApprovalWindow
                    Dispatcher.Invoke(() =>
                    {
                        SetAppState(AppStateIcon.WaitingForApproval, "Waiting for Approval");

                        // Notify user of required approval
                        _notifyIcon?.ShowBalloonTip(
                            "Permission Required",
                            $"Authorization needed for command or tool action:\n{permissionType}",
                            BalloonIcon.Warning
                        );
                        
                        var approvalWin = new ApprovalWindow(requestId, permissionType, detail);
                        var result = approvalWin.ShowDialog();
                        var decision = approvalWin.UserDecision; // allow, deny, always

                        // Revert app state to Executing
                        SetAppState(AppStateIcon.Executing, "Executing...");

                        Task.Run(async () =>
                        {
                            try
                            {
                                await _openCodeClient!.SendPermissionReplyAsync(requestId, decision);
                            }
                            catch (Exception ex)
                            {
                                File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "approval-reply-error.log"), ex.ToString());
                            }
                        });
                    });
                }
            }
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void OnServerProcessExited(int exitCode)
        {
            Dispatcher.Invoke(() => SetAppState(AppStateIcon.Error, $"Engine Stopped ({exitCode})"));

            // Fix 1.2: auto-restart the engine (up to 3 attempts)
            if (_serverRestartAttempts < 3)
            {
                _serverRestartAttempts++;
                Task.Run(async () =>
                {
                    await Task.Delay(3000);
                    try
                    {
                        var binaryManager = new BinaryManager();
                        var (binaryPath, _) = binaryManager.ResolveBinary();
                        if (binaryPath != null)
                        {
                            var workingDir = AppDomain.CurrentDomain.BaseDirectory;
                            await _openCodeServer!.StartAsync(binaryPath, workingDir);
                            _serverRestartAttempts = 0;
                        }
                    }
                    catch (Exception ex)
                    {
                        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "engine-startup-crash.log"), ex.ToString());
                        Dispatcher.Invoke(() => SetAppState(AppStateIcon.Error, "Engine Restart Failed"));
                    }
                });
            }
        }

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void SetAppState(AppStateIcon state, string statusText)
        {
            if (_notifyIcon == null || _statusHeaderItem == null) return;

            _statusHeaderItem.Header = $"GAS: {statusText}";
            _notifyIcon.ToolTipText = $"GAS: {statusText}";

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
                case AppStateIcon.WaitingForApproval:
                    _notifyIcon.Icon = _iconWaitingForApproval;
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

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private void ShutdownApp()
        {
            _hotkeyManager?.Dispose();
            _commandBar?.Close();
            _drawer?.Close();

            _openCodeServer?.Dispose();
            _notifyIcon?.Dispose();
            
            _iconIdle?.Dispose();
            _iconThinking?.Dispose();
            _iconExecuting?.Dispose();
            _iconError?.Dispose();
            _iconWaitingForApproval?.Dispose();

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
            Error,
            WaitingForApproval
        }
    }
}

