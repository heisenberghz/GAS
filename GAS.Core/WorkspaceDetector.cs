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
    /// Detects the current workspace directory using a priority chain:
    /// 1. The foreground window's folder (File Explorer, VS Code, Visual Studio, terminals)
    /// 2. Saved LastWorkspacePath from settings (if directory still exists)
    /// 3. User home directory as final fallback
    /// </summary>
    public class WorkspaceInfo
    {
        public string Path { get; set; } = string.Empty;
        public string Method { get; set; } = string.Empty;
        public string ProjectName { get; set; } = string.Empty;
    }

    public static class WorkspaceDetector
    {
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        /// <summary>
        /// Returns the best workspace path available.
        /// </summary>
        public static WorkspaceInfo Detect(string? savedPath, IntPtr foregroundHwnd = default)
        {
            Debug.WriteLine($"[WD] Detect: hwnd={foregroundHwnd}, saved={savedPath}");

            if (foregroundHwnd != IntPtr.Zero)
            {
                GetWindowThreadProcessId(foregroundHwnd, out uint fgPid);
                string processName = "";
                try
                {
                    using var proc = Process.GetProcessById((int)fgPid);
                    processName = proc.ProcessName;
                }
                catch { }

                Debug.WriteLine($"[WD] Foreground: PID={fgPid}, Name={processName}");

                // ─── File Explorer ─────────────────────────────────
                if (processName.Equals("explorer", StringComparison.OrdinalIgnoreCase))
                {
#pragma warning disable CA1416
                    var explorerPath = TryGetFileExplorerFolderByHwnd(foregroundHwnd);
#pragma warning restore CA1416
                    if (explorerPath != null)
                        return MakeResult(explorerPath, "File Explorer");
                }

                // ─── VS Code ──────────────────────────────────────
                if (processName.Equals("Code", StringComparison.OrdinalIgnoreCase))
                {
                    // Strategy 1: Parse window title (most reliable)
                    var titlePath = TryGetVsCodePathFromTitle(foregroundHwnd);
                    if (titlePath != null)
                        return MakeResult(titlePath, "VS Code (title)");

                    // Strategy 2: Walk the process tree to find the matching instance
                    var treePath = TryGetVsCodeFolderByProcessTree(fgPid);
                    if (treePath != null)
                        return MakeResult(treePath, "VS Code (tree)");

                    // Strategy 3: CWD of the process
                    var cwdPath = TryGetWorkingDirectory((int)fgPid);
                    if (cwdPath != null)
                        return MakeResult(cwdPath, "VS Code (cwd)");
                }

                // ─── Visual Studio ────────────────────────────────
                if (processName.Equals("devenv", StringComparison.OrdinalIgnoreCase))
                {
                    var vsPath = TryGetVisualStudioFolder(fgPid);
                    if (vsPath != null)
                        return MakeResult(vsPath, "Visual Studio");
                }

                // ─── Terminal (Windows Terminal, ConHost, PowerShell, cmd) ─
                if (processName.Equals("WindowsTerminal", StringComparison.OrdinalIgnoreCase) ||
                    processName.Equals("pwsh", StringComparison.OrdinalIgnoreCase) ||
                    processName.Equals("powershell", StringComparison.OrdinalIgnoreCase) ||
                    processName.Equals("cmd", StringComparison.OrdinalIgnoreCase))
                {
                    var termPath = TryGetTerminalWorkspace(foregroundHwnd, fgPid);
                    if (termPath != null)
                        return MakeResult(termPath, "Terminal");
                }

                Debug.WriteLine($"[WD] Foreground '{processName}' not recognized or detection failed");
            }

            // ─── Fallback: scan for any running IDE ──────────────
            Debug.WriteLine("[WD] Scanning all processes for IDE workspaces");

            var anyVsCode = TryGetMostRecentVsCodeWorkspace();
            if (anyVsCode != null)
                return MakeResult(anyVsCode, "VS Code (scan)");

            var anyVs = TryGetVisualStudioFolder(0);
            if (anyVs != null)
                return MakeResult(anyVs, "Visual Studio (scan)");

            // ─── Saved path ──────────────────────────────────────
            if (!string.IsNullOrWhiteSpace(savedPath) && Directory.Exists(savedPath))
                return MakeResult(savedPath, "Saved Settings");

            // ─── Home directory ──────────────────────────────────
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return new WorkspaceInfo { Path = home, Method = "Home Directory", ProjectName = "Home" };
        }

        // ────────────────────────────────────────────────────────────────
        //  Result builder
        // ────────────────────────────────────────────────────────────────

        private static WorkspaceInfo MakeResult(string path, string method)
        {
            var name = DeriveProjectName(path);
            Debug.WriteLine($"[WD] ✓ {method}: {path} → '{name}'");
            return new WorkspaceInfo { Path = path, Method = method, ProjectName = name };
        }

        /// <summary>
        /// Derives a friendly project name from the workspace path.
        /// Looks for .sln, package.json, .git, then falls back to directory name.
        /// </summary>
        public static string DeriveProjectName(string path)
        {
            if (string.IsNullOrEmpty(path) || !Directory.Exists(path))
                return "Unknown";

            try
            {
                // .sln file → use its name
                var sln = Directory.GetFiles(path, "*.sln").FirstOrDefault();
                if (sln != null)
                    return System.IO.Path.GetFileNameWithoutExtension(sln);

                // .csproj file → use its name
                var csproj = Directory.GetFiles(path, "*.csproj").FirstOrDefault();
                if (csproj != null)
                    return System.IO.Path.GetFileNameWithoutExtension(csproj);

                // package.json → read "name"
                var pkgJson = System.IO.Path.Combine(path, "package.json");
                if (File.Exists(pkgJson))
                {
                    try
                    {
                        var text = File.ReadAllText(pkgJson);
                        var m = Regex.Match(text, "\"name\"\\s*:\\s*\"([^\"]+)\"");
                        if (m.Success) return m.Groups[1].Value;
                    }
                    catch { }
                }

                // Cargo.toml, go.mod etc → directory name is fine
            }
            catch { }

            // Fallback: directory name
            return new DirectoryInfo(path).Name;
        }

        // ────────────────────────────────────────────────────────────────
        //  VS Code: Primary — parse window title
        // ────────────────────────────────────────────────────────────────
        //  VS Code titles look like:
        //    "App.xaml.cs - GAS - Visual Studio Code"
        //    "folder-name - Visual Studio Code"
        //    "Welcome - GAS - Visual Studio Code"
        // The second-to-last segment before " - Visual Studio Code" is the folder name.

        private static string? TryGetVsCodePathFromTitle(IntPtr hwnd)
        {
            try
            {
                int len = GetWindowTextLength(hwnd);
                if (len <= 0) return null;

                var sb = new System.Text.StringBuilder(len + 1);
                GetWindowText(hwnd, sb, len + 1);
                var title = sb.ToString();

                Debug.WriteLine($"[WD] VS Code title: '{title}'");

                // Pattern: "something - WORKSPACE - Visual Studio Code"
                // or      "WORKSPACE - Visual Studio Code"
                const string suffix = " - Visual Studio Code";
                if (!title.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
                    return null;

                var withoutSuffix = title[..^suffix.Length];
                // Now split by " - " and take the last segment as workspace name
                var parts = withoutSuffix.Split(new[] { " - " }, StringSplitOptions.RemoveEmptyEntries);
                var wsName = parts.Length > 0 ? parts[^1].Trim() : null;
                if (string.IsNullOrEmpty(wsName)) return null;

                Debug.WriteLine($"[WD] VS Code workspace name from title: '{wsName}'");

                // Now find that folder: check all Code processes for --folder-uri containing this name
                foreach (var p in Process.GetProcessesByName("Code"))
                {
                    try
                    {
                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine == null) continue;

                        var match = Regex.Match(cmdLine, @"--folder-uri=file:///([^""\s]+)", RegexOptions.IgnoreCase);
                        if (!match.Success) continue;

                        var rawPath = match.Groups[1].Value;
                        var decoded = Uri.UnescapeDataString(rawPath).Replace('/', '\\');
                        if (!Directory.Exists(decoded)) continue;

                        var dirName = new DirectoryInfo(decoded).Name;
                        if (dirName.Equals(wsName, StringComparison.OrdinalIgnoreCase))
                        {
                            Debug.WriteLine($"[WD] VS Code title→path match: '{decoded}'");
                            return decoded;
                        }
                    }
                    catch { }
                    finally { p.Dispose(); }
                }

                // If no --folder-uri matched, try to find by scanning recent folders
                // Check common paths: user profile, D:\, C:\Users\...\source
                var candidates = new[]
                {
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    @"D:\",
                    @"C:\",
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "source", "repos"),
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Projects"),
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Documents"),
                };

                foreach (var root in candidates)
                {
                    if (!Directory.Exists(root)) continue;
                    var candidate = System.IO.Path.Combine(root, wsName);
                    if (Directory.Exists(candidate))
                    {
                        Debug.WriteLine($"[WD] VS Code title→disk scan match: '{candidate}'");
                        return candidate;
                    }
                }
            }
            catch (Exception ex) { Debug.WriteLine($"[WD] VS Code title parse failed: {ex.Message}"); }
            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  VS Code: process tree walk
        // ────────────────────────────────────────────────────────────────
        //  Walk up from foreground PID to find parent Code.exe with --folder-uri

        private static string? TryGetVsCodeFolderByProcessTree(uint startPid)
        {
            try
            {
                var visited = new HashSet<uint>();
                var current = startPid;

                while (current > 0 && visited.Add(current))
                {
                    var cmdLine = GetCommandLine((int)current);
                    if (cmdLine != null)
                    {
                        var m = Regex.Match(cmdLine, @"--folder-uri=file:///([^""\s]+)", RegexOptions.IgnoreCase);
                        if (m.Success)
                        {
                            var decoded = Uri.UnescapeDataString(m.Groups[1].Value).Replace('/', '\\');
                            if (Directory.Exists(decoded)) return decoded;
                        }
                    }

                    current = GetParentProcessId(current);
                }
            }
            catch (Exception ex) { Debug.WriteLine($"[WD] Process tree walk failed: {ex.Message}"); }
            return null;
        }

        /// <summary>
        /// Gets the most recently started VS Code instance's workspace.
        /// </summary>
        private static string? TryGetMostRecentVsCodeWorkspace()
        {
            try
            {
                var codeProcesses = Process.GetProcessesByName("Code")
                    .OrderByDescending(p => { try { return p.StartTime; } catch { return DateTime.MinValue; } })
                    .ToArray();

                foreach (var p in codeProcesses)
                {
                    try
                    {
                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine == null) continue;

                        var m = Regex.Match(cmdLine, @"--folder-uri=file:///([^""\s]+)", RegexOptions.IgnoreCase);
                        if (!m.Success) continue;

                        var decoded = Uri.UnescapeDataString(m.Groups[1].Value).Replace('/', '\\');
                        if (Directory.Exists(decoded)) return decoded;
                    }
                    catch { }
                    finally { p.Dispose(); }
                }
            }
            catch { }
            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  File Explorer: match by exact HWND via Shell COM
        // ────────────────────────────────────────────────────────────────

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private static string? TryGetFileExplorerFolderByHwnd(IntPtr targetHwnd)
        {
            try
            {
                Type? shellType = Type.GetTypeFromProgID("Shell.Application");
                if (shellType == null) return null;

                object? shell = Activator.CreateInstance(shellType);
                if (shell == null) return null;

                object? windows = shellType.InvokeMember("Windows",
                    System.Reflection.BindingFlags.InvokeMethod, null, shell, null);
                if (windows == null) return null;

                int count = (int)(windows.GetType().InvokeMember("Count",
                    System.Reflection.BindingFlags.GetProperty, null, windows, null) ?? 0);

                for (int i = 0; i < count; i++)
                {
                    try
                    {
                        object? window = windows.GetType().InvokeMember("Item",
                            System.Reflection.BindingFlags.InvokeMethod, null, windows, new object[] { i });
                        if (window == null) continue;

                        var hwndObj = window.GetType().InvokeMember("HWND",
                            System.Reflection.BindingFlags.GetProperty, null, window, null);
                        IntPtr windowHwnd = new IntPtr(Convert.ToInt64(hwndObj));

                        if (windowHwnd != targetHwnd) continue;

                        object? document = window.GetType().InvokeMember("Document",
                            System.Reflection.BindingFlags.GetProperty, null, window, null);
                        if (document == null) continue;

                        object? folder = document.GetType().InvokeMember("Folder",
                            System.Reflection.BindingFlags.GetProperty, null, document, null);
                        if (folder == null) continue;

                        object? self = folder.GetType().InvokeMember("Self",
                            System.Reflection.BindingFlags.GetProperty, null, folder, null);
                        if (self == null) continue;

                        string? path = self.GetType().InvokeMember("Path",
                            System.Reflection.BindingFlags.GetProperty, null, self, null) as string;

                        if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path))
                            return path;
                    }
                    catch { }
                }
            }
            catch (Exception ex) { Debug.WriteLine($"[WD] Shell COM: {ex.Message}"); }
            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  Visual Studio
        // ────────────────────────────────────────────────────────────────

        private static string? TryGetVisualStudioFolder(uint targetPid)
        {
            try
            {
                var vsProcesses = Process.GetProcessesByName("devenv");
                foreach (var p in vsProcesses)
                {
                    if (targetPid > 0 && p.Id != (int)targetPid) { p.Dispose(); continue; }
                    try
                    {
                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine != null)
                        {
                            var m = Regex.Match(cmdLine, "\"([^\"]+\\.sln)\"", RegexOptions.IgnoreCase);
                            if (m.Success)
                            {
                                var dir = System.IO.Path.GetDirectoryName(m.Groups[1].Value);
                                if (dir != null && Directory.Exists(dir))
                                    return dir;
                            }
                        }
                    }
                    catch { }
                    finally { p.Dispose(); }
                }
            }
            catch { }
            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  Terminal workspace detection (parse CWD from title or process)
        // ────────────────────────────────────────────────────────────────

        private static string? TryGetTerminalWorkspace(IntPtr hwnd, uint pid)
        {
            try
            {
                // Windows Terminal title usually contains the CWD
                int len = GetWindowTextLength(hwnd);
                if (len > 0)
                {
                    var sb = new System.Text.StringBuilder(len + 1);
                    GetWindowText(hwnd, sb, len + 1);
                    var title = sb.ToString();

                    // Patterns: "PS D:\GAS\GAS>", "C:\Users\...", etc.
                    var m = Regex.Match(title, @"([A-Z]:\\[^\s>|]+)", RegexOptions.IgnoreCase);
                    if (m.Success && Directory.Exists(m.Value))
                        return m.Value;
                }

                // Try CWD of child processes (pwsh, cmd)
                var cwd = TryGetWorkingDirectory((int)pid);
                if (cwd != null) return cwd;
            }
            catch { }
            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  Process utilities
        // ────────────────────────────────────────────────────────────────

        /// <summary>
        /// Reads the full command line of a process via WMI.
        /// </summary>
        private static string? GetCommandLine(int pid)
        {
            try
            {
#pragma warning disable CA1416
                using var searcher = new System.Management.ManagementObjectSearcher(
                    $"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {pid}");
                foreach (System.Management.ManagementObject obj in searcher.Get())
                    return obj["CommandLine"]?.ToString();
#pragma warning restore CA1416
            }
            catch { }
            return null;
        }

        /// <summary>
        /// Gets the parent process ID via WMI.
        /// </summary>
        private static uint GetParentProcessId(uint pid)
        {
            try
            {
#pragma warning disable CA1416
                using var searcher = new System.Management.ManagementObjectSearcher(
                    $"SELECT ParentProcessId FROM Win32_Process WHERE ProcessId = {pid}");
                foreach (System.Management.ManagementObject obj in searcher.Get())
                    return Convert.ToUInt32(obj["ParentProcessId"]);
#pragma warning restore CA1416
            }
            catch { }
            return 0;
        }

        /// <summary>
        /// Gets the working directory of a process via WMI ExecutablePath + cmdline heuristics.
        /// </summary>
        private static string? TryGetWorkingDirectory(int pid)
        {
            try
            {
#pragma warning disable CA1416
                using var searcher = new System.Management.ManagementObjectSearcher(
                    $"SELECT ExecutablePath FROM Win32_Process WHERE ProcessId = {pid}");
                foreach (System.Management.ManagementObject obj in searcher.Get())
                {
                    var exePath = obj["ExecutablePath"]?.ToString();
                    if (exePath != null)
                    {
                        var dir = System.IO.Path.GetDirectoryName(exePath);
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
