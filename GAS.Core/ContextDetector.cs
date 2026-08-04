using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace GAS.Core
{
    /// <summary>
    /// Represents the full context of the user's active window/application.
    /// </summary>
    public class ContextInfo
    {
        /// <summary>Friendly application name (e.g. "ChatGPT", "Antigravity IDE", "Windows Terminal", "Rider")</summary>
        public string AppName { get; set; } = string.Empty;

        /// <summary>The resolved workspace path on disk if available; null if no local code workspace is associated.</summary>
        public string? WorkspacePath { get; set; }

        /// <summary>Friendly project name (e.g. "GAS") or app name if no workspace exists.</summary>
        public string ProjectName { get; set; } = string.Empty;

        /// <summary>Description of how context was detected</summary>
        public string DetectionMethod { get; set; } = string.Empty;

        /// <summary>True if a valid local code workspace directory was detected</summary>
        public bool HasWorkspace { get; set; }
    }

    /// <summary>
    /// Robust, universal context detector inspired by Motive.
    /// Inspects the active foreground application, process, command line, CWD, and window title
    /// across IDEs, terminals, file managers, browsers, and desktop AI apps.
    /// </summary>
    public static class ContextDetector
    {
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        // ─────────────────────────────────────────────────────────────
        //  App Category Definitions
        // ─────────────────────────────────────────────────────────────

        private static readonly Dictionary<string, string> KnownAppNames = new(StringComparer.OrdinalIgnoreCase)
        {
            { "Code", "VS Code" },
            { "Code - Insiders", "VS Code Insiders" },
            { "Antigravity IDE", "Antigravity IDE" },
            { "Antigravity", "Antigravity IDE" },
            { "Cursor", "Cursor" },
            { "Windsurf", "Windsurf" },
            { "codium", "VSCodium" },
            { "VSCodium", "VSCodium" },
            { "devenv", "Visual Studio" },
            { "rider64", "JetBrains Rider" },
            { "idea64", "IntelliJ IDEA" },
            { "pycharm64", "PyCharm" },
            { "webstorm64", "WebStorm" },
            { "clion64", "CLion" },
            { "goland64", "GoLand" },
            { "datagrip64", "DataGrip" },
            { "phpstorm64", "PhpStorm" },
            { "rubymine64", "RubyMine" },
            { "explorer", "File Explorer" },
            { "WindowsTerminal", "Windows Terminal" },
            { "pwsh", "PowerShell" },
            { "powershell", "PowerShell" },
            { "cmd", "Command Prompt" },
            { "mintty", "Git Bash" },
            { "bash", "Git Bash" },
            { "wsl", "WSL" },
            { "ChatGPT", "ChatGPT" },
            { "Claude", "Claude" },
            { "chrome", "Google Chrome" },
            { "msedge", "Microsoft Edge" },
            { "brave", "Brave Browser" },
            { "firefox", "Firefox" }
        };

        // ─────────────────────────────────────────────────────────────
        //  Public Detector Entry Point
        // ─────────────────────────────────────────────────────────────

        public static ContextInfo Detect(IntPtr foregroundHwnd, string? savedWorkspacePath = null)
        {
            if (foregroundHwnd != IntPtr.Zero)
            {
                GetWindowThreadProcessId(foregroundHwnd, out uint pid);
                string procName = string.Empty;
                try
                {
                    using var proc = Process.GetProcessById((int)pid);
                    procName = proc.ProcessName;
                }
                catch { }

                var title = GetWindowTitle(foregroundHwnd);
                var friendlyAppName = ResolveAppName(procName, title);

                Debug.WriteLine($"[ContextDetector] Foreground HWND={foregroundHwnd}, PID={pid}, Proc='{procName}', App='{friendlyAppName}', Title='{title}'");

                // 1. File Explorer
                if (procName.Equals("explorer", StringComparison.OrdinalIgnoreCase))
                {
#pragma warning disable CA1416
                    var explorerPath = TryGetFileExplorerFolder(foregroundHwnd);
#pragma warning restore CA1416
                    if (explorerPath != null && Directory.Exists(explorerPath))
                    {
                        return BuildContext(friendlyAppName, explorerPath, "File Explorer");
                    }
                }

                // 2. IDEs & Code Editors
                if (IsIdeProcess(procName, title))
                {
                    var idePath = ResolveIdeWorkspace(procName, title, pid, savedWorkspacePath);
                    if (idePath != null && Directory.Exists(idePath))
                    {
                        return BuildContext(friendlyAppName, idePath, $"{friendlyAppName} Window");
                    }
                }

                // 3. Terminals & Shells
                if (IsTerminalProcess(procName))
                {
                    var termPath = ResolveTerminalWorkspace(title, pid);
                    if (termPath != null && Directory.Exists(termPath))
                    {
                        return BuildContext(friendlyAppName, termPath, $"{friendlyAppName} Directory");
                    }
                }

                // 4. Non-Code App (e.g. ChatGPT, Claude, Chrome, Spotify)
                // Extract title path if explicit path exists in title
                var pathInTitle = ExtractPathFromString(title);
                if (pathInTitle != null && Directory.Exists(pathInTitle))
                {
                    return BuildContext(friendlyAppName, pathInTitle, "Title Path");
                }

                // Return true App Context without forcing a fake workspace
                return new ContextInfo
                {
                    AppName = friendlyAppName,
                    WorkspacePath = null,
                    ProjectName = friendlyAppName,
                    DetectionMethod = "Foreground App",
                    HasWorkspace = false
                };
            }

            // Fallback: Scan running IDE processes if no foreground window was provided
            var scannedIde = TryScanRunningIdeProcesses(savedWorkspacePath);
            if (scannedIde.HasValue)
            {
                return BuildContext(scannedIde.Value.AppName, scannedIde.Value.Path, "Running IDE Scan");
            }

            // Fallback: Saved Workspace Path if valid
            if (!string.IsNullOrWhiteSpace(savedWorkspacePath) && Directory.Exists(savedWorkspacePath))
            {
                return BuildContext("GAS System", savedWorkspacePath, "Saved Settings");
            }

            // Fallback: Home Directory
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return BuildContext("GAS System", home, "Home Directory");
        }

        // ─────────────────────────────────────────────────────────────
        //  Category Helpers
        // ─────────────────────────────────────────────────────────────

        private static bool IsIdeProcess(string procName, string title)
        {
            if (KnownAppNames.ContainsKey(procName) &&
                (procName.Contains("Code", StringComparison.OrdinalIgnoreCase) ||
                 procName.Contains("Antigravity", StringComparison.OrdinalIgnoreCase) ||
                 procName.Contains("Cursor", StringComparison.OrdinalIgnoreCase) ||
                 procName.Contains("Windsurf", StringComparison.OrdinalIgnoreCase) ||
                 procName.Equals("devenv", StringComparison.OrdinalIgnoreCase) ||
                 procName.Contains("rider", StringComparison.OrdinalIgnoreCase) ||
                 procName.Contains("idea", StringComparison.OrdinalIgnoreCase) ||
                 procName.Contains("pycharm", StringComparison.OrdinalIgnoreCase) ||
                 procName.Contains("webstorm", StringComparison.OrdinalIgnoreCase)))
                return true;

            if (title.Contains("Visual Studio Code", StringComparison.OrdinalIgnoreCase) ||
                title.Contains("Antigravity IDE", StringComparison.OrdinalIgnoreCase) ||
                title.Contains("Cursor", StringComparison.OrdinalIgnoreCase) ||
                title.Contains("Windsurf", StringComparison.OrdinalIgnoreCase))
                return true;

            return false;
        }

        private static bool IsTerminalProcess(string procName) =>
            procName.Equals("WindowsTerminal", StringComparison.OrdinalIgnoreCase) ||
            procName.Equals("pwsh", StringComparison.OrdinalIgnoreCase) ||
            procName.Equals("powershell", StringComparison.OrdinalIgnoreCase) ||
            procName.Equals("cmd", StringComparison.OrdinalIgnoreCase) ||
            procName.Equals("mintty", StringComparison.OrdinalIgnoreCase) ||
            procName.Equals("bash", StringComparison.OrdinalIgnoreCase);

        private static string ResolveAppName(string procName, string title)
        {
            if (KnownAppNames.TryGetValue(procName, out var name))
                return name;

            if (title.Contains("ChatGPT", StringComparison.OrdinalIgnoreCase)) return "ChatGPT";
            if (title.Contains("Claude", StringComparison.OrdinalIgnoreCase)) return "Claude";

            return string.IsNullOrWhiteSpace(procName) ? "Desktop Application" : procName;
        }

        // ─────────────────────────────────────────────────────────────
        //  IDE Workspace Resolution
        // ─────────────────────────────────────────────────────────────

        private static string? ResolveIdeWorkspace(string procName, string title, uint pid, string? savedPath)
        {
            // A. Title-based resolution
            var titlePath = ParseWorkspaceFromTitle(title, savedPath);
            if (titlePath != null) return titlePath;

            // B. WMI command-line inspection
            var cmdLinePath = GetWorkspaceFromCommandLine((int)pid);
            if (cmdLinePath != null) return cmdLinePath;

            // C. Working directory inspection
            var cwd = TryGetWorkingDirectory((int)pid);
            if (cwd != null) return cwd;

            return null;
        }

        private static string? ParseWorkspaceFromTitle(string title, string? savedPath)
        {
            if (string.IsNullOrWhiteSpace(title)) return null;

            // Extract path if title contains absolute Windows path
            var pathInTitle = ExtractPathFromString(title);
            if (pathInTitle != null) return pathInTitle;

            // Strip known app suffixes
            var clean = Regex.Replace(title, @"\s*[-–—]\s*(Visual Studio Code|Antigravity IDE|Cursor|Windsurf|VSCodium|JetBrains Rider|Visual Studio).*", "", RegexOptions.IgnoreCase).Trim();

            var parts = clean.Split(new[] { " - ", " – ", " — " }, StringSplitOptions.RemoveEmptyEntries)
                             .Select(p => p.Trim())
                             .Where(p => !string.IsNullOrEmpty(p))
                             .ToList();

            if (parts.Count == 0) return null;

            // Match candidate names against savedPath or disk folders
            foreach (var candidate in parts)
            {
                if (Path.HasExtension(candidate) && !candidate.EndsWith(".sln") && !candidate.EndsWith(".csproj"))
                    continue;

                // Check saved path
                if (!string.IsNullOrWhiteSpace(savedPath) && Directory.Exists(savedPath))
                {
                    var savedName = new DirectoryInfo(savedPath.TrimEnd('\\', '/')).Name;
                    if (candidate.Equals(savedName, StringComparison.OrdinalIgnoreCase))
                        return savedPath;
                }

                // Check active execution hierarchy
                var currentBase = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
                var dirInfo = new DirectoryInfo(currentBase);
                while (dirInfo != null)
                {
                    if (candidate.Equals(dirInfo.Name, StringComparison.OrdinalIgnoreCase))
                        return dirInfo.FullName;
                    dirInfo = dirInfo.Parent;
                }

                // Search disk roots
                var diskPath = SearchFolderOnDisk(candidate);
                if (diskPath != null) return diskPath;
            }

            return null;
        }

        // ─────────────────────────────────────────────────────────────
        //  Terminal & Shell Resolution
        // ─────────────────────────────────────────────────────────────

        private static string? ResolveTerminalWorkspace(string title, uint pid)
        {
            var pathInTitle = ExtractPathFromString(title);
            if (pathInTitle != null) return pathInTitle;

            var cwd = TryGetWorkingDirectory((int)pid);
            if (cwd != null) return cwd;

            return null;
        }

        // ─────────────────────────────────────────────────────────────
        //  File Explorer COM Resolution
        // ─────────────────────────────────────────────────────────────

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private static string? TryGetFileExplorerFolder(IntPtr targetHwnd)
        {
            try
            {
                Type? shellType = Type.GetTypeFromProgID("Shell.Application");
                if (shellType == null) return null;

                object? shell = Activator.CreateInstance(shellType);
                if (shell == null) return null;

                object? windows = shellType.InvokeMember("Windows", System.Reflection.BindingFlags.InvokeMethod, null, shell, null);
                if (windows == null) return null;

                int count = (int)(windows.GetType().InvokeMember("Count", System.Reflection.BindingFlags.GetProperty, null, windows, null) ?? 0);

                for (int i = 0; i < count; i++)
                {
                    try
                    {
                        object? window = windows.GetType().InvokeMember("Item", System.Reflection.BindingFlags.InvokeMethod, null, windows, new object[] { i });
                        if (window == null) continue;

                        var hwndObj = window.GetType().InvokeMember("HWND", System.Reflection.BindingFlags.GetProperty, null, window, null);
                        IntPtr windowHwnd = new IntPtr(Convert.ToInt64(hwndObj));

                        if (windowHwnd != targetHwnd) continue;

                        object? document = window.GetType().InvokeMember("Document", System.Reflection.BindingFlags.GetProperty, null, window, null);
                        object? folder   = document?.GetType().InvokeMember("Folder", System.Reflection.BindingFlags.GetProperty, null, document, null);
                        object? self     = folder?.GetType().InvokeMember("Self", System.Reflection.BindingFlags.GetProperty, null, folder, null);
                        string? path     = self?.GetType().InvokeMember("Path", System.Reflection.BindingFlags.GetProperty, null, self, null) as string;

                        if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path))
                            return path;
                    }
                    catch { }
                }
            }
            catch { }
            return null;
        }

        // ─────────────────────────────────────────────────────────────
        //  Running Process Scanner Fallback
        // ─────────────────────────────────────────────────────────────

        private struct ScannedIdeResult
        {
            public string AppName;
            public string Path;
        }

        private static ScannedIdeResult? TryScanRunningIdeProcesses(string? savedPath)
        {
            foreach (var kvp in KnownAppNames)
            {
                var procName = kvp.Key;
                var appName  = kvp.Value;
                try
                {
                    var procs = Process.GetProcessesByName(procName);
                    foreach (var p in procs)
                    {
                        try
                        {
                            var cmdLine = GetCommandLine(p.Id);
                            if (cmdLine != null)
                            {
                                var folder = ExtractFolderFromCmdLine(cmdLine);
                                if (folder != null)
                                {
                                    if (!string.IsNullOrWhiteSpace(savedPath) && folder.Equals(savedPath, StringComparison.OrdinalIgnoreCase))
                                        return new ScannedIdeResult { AppName = appName, Path = folder };

                                    return new ScannedIdeResult { AppName = appName, Path = folder };
                                }
                            }
                        }
                        catch { }
                        finally { p.Dispose(); }
                    }
                }
                catch { }
            }
            return null;
        }

        // ─────────────────────────────────────────────────────────────
        //  Utilities & Helpers
        // ─────────────────────────────────────────────────────────────

        public static ContextInfo BuildContext(string appName, string workspacePath, string method)
        {
            var projectName = WorkspaceDetector.DeriveProjectName(workspacePath);
            return new ContextInfo
            {
                AppName = appName,
                WorkspacePath = workspacePath,
                ProjectName = projectName,
                DetectionMethod = method,
                HasWorkspace = true
            };
        }

        private static string GetWindowTitle(IntPtr hwnd)
        {
            try
            {
                int len = GetWindowTextLength(hwnd);
                if (len <= 0) return string.Empty;
                var sb = new System.Text.StringBuilder(len + 1);
                GetWindowText(hwnd, sb, len + 1);
                return sb.ToString();
            }
            catch { return string.Empty; }
        }

        private static string? ExtractPathFromString(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return null;
            var m = Regex.Match(text, @"([A-Za-z]:\\[^\s><|""\?]+)", RegexOptions.IgnoreCase);
            if (m.Success)
            {
                var candidate = m.Value.TrimEnd('.', ',', ';', ':', ')', ']');
                if (Directory.Exists(candidate)) return candidate;
            }
            return null;
        }

        private static string? GetWorkspaceFromCommandLine(int pid)
        {
            var cmdLine = GetCommandLine(pid);
            if (cmdLine == null) return null;
            return ExtractFolderFromCmdLine(cmdLine);
        }

        private static string? ExtractFolderFromCmdLine(string cmdLine)
        {
            if (string.IsNullOrWhiteSpace(cmdLine)) return null;

            var m1 = Regex.Match(cmdLine, @"--folder-uri=file:///([^""\s]+)", RegexOptions.IgnoreCase);
            if (m1.Success)
            {
                var decoded = Uri.UnescapeDataString(m1.Groups[1].Value).Replace('/', '\\');
                if (Directory.Exists(decoded)) return decoded;
            }

            var m2 = Regex.Match(cmdLine, @"--workspace=file:///([^""\s]+)", RegexOptions.IgnoreCase);
            if (m2.Success)
            {
                var decoded = Uri.UnescapeDataString(m2.Groups[1].Value).Replace('/', '\\');
                var dir = Path.GetDirectoryName(decoded);
                if (dir != null && Directory.Exists(dir)) return dir;
            }

            var m3 = Regex.Match(cmdLine, @"\""([^\s\""]+\\.sln)\""", RegexOptions.IgnoreCase);
            if (m3.Success)
            {
                var dir = Path.GetDirectoryName(m3.Groups[1].Value);
                if (dir != null && Directory.Exists(dir)) return dir;
            }

            return null;
        }

        private static string? SearchFolderOnDisk(string folderName)
        {
            if (string.IsNullOrWhiteSpace(folderName)) return null;

            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var searchRoots = new[]
            {
                @"D:\", @"D:\src", @"C:\src", @"D:\Projects",
                Path.Combine(userProfile, "source", "repos"),
                Path.Combine(userProfile, "Projects"),
                Path.Combine(userProfile, "Documents"),
                @"C:\"
            };

            foreach (var root in searchRoots)
            {
                try
                {
                    if (!Directory.Exists(root)) continue;
                    var target = Path.Combine(root, folderName);
                    if (Directory.Exists(target)) return target;
                }
                catch { }
            }
            return null;
        }

        private static string? GetCommandLine(int pid)
        {
            try
            {
#pragma warning disable CA1416
                using var searcher = new System.Management.ManagementObjectSearcher($"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {pid}");
                foreach (System.Management.ManagementObject obj in searcher.Get())
                    return obj["CommandLine"]?.ToString();
#pragma warning restore CA1416
            }
            catch { }
            return null;
        }

        private static string? TryGetWorkingDirectory(int pid)
        {
            try
            {
#pragma warning disable CA1416
                using var searcher = new System.Management.ManagementObjectSearcher($"SELECT ExecutablePath FROM Win32_Process WHERE ProcessId = {pid}");
                foreach (System.Management.ManagementObject obj in searcher.Get())
                {
                    var exePath = obj["ExecutablePath"]?.ToString();
                    if (exePath != null)
                    {
                        var dir = Path.GetDirectoryName(exePath);
                        if (dir != null && Directory.Exists(dir) &&
                            !dir.StartsWith(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), StringComparison.OrdinalIgnoreCase) &&
                            !dir.StartsWith(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), StringComparison.OrdinalIgnoreCase) &&
                            !dir.Contains("WindowsApps", StringComparison.OrdinalIgnoreCase))
                            return dir;
                    }
                }
#pragma warning restore CA1416
            }
            catch { }
            return null;
        }
    }
}
