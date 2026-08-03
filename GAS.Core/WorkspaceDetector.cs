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
    /// 1. Foreground window (VS Code, Antigravity IDE, Cursor, Windsurf, Visual Studio, Explorer, Terminals)
    /// 2. Active running IDE processes scan
    /// 3. Saved LastWorkspacePath from settings
    /// 4. Home directory fallback
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

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        private static readonly string[] VsCodeProcessNames = new[]
        {
            "Code", "Code - Insiders", "Antigravity IDE", "Antigravity",
            "Cursor", "Windsurf", "codium", "VSCodium", "electron"
        };

        private static readonly string[] VsCodeTitleSuffixes = new[]
        {
            " - Antigravity IDE",
            " - Visual Studio Code",
            " - Visual Studio Code - Insiders",
            " - Cursor",
            " - Windsurf",
            " - VSCodium",
            " - Code"
        };

        /// <summary>
        /// Returns the best workspace path available.
        /// </summary>
        public static WorkspaceInfo Detect(string? savedPath, IntPtr foregroundHwnd = default)
        {
            Debug.WriteLine($"[WD] Detect: hwnd={foregroundHwnd}, savedPath={savedPath}");

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

                var windowTitle = GetTitle(foregroundHwnd);
                Debug.WriteLine($"[WD] Foreground: PID={fgPid}, Name='{processName}', Title='{windowTitle}'");

                // ─── 1. File Explorer ──────────────────────────────
                if (processName.Equals("explorer", StringComparison.OrdinalIgnoreCase))
                {
#pragma warning disable CA1416
                    var explorerPath = TryGetFileExplorerFolderByHwnd(foregroundHwnd);
#pragma warning restore CA1416
                    if (explorerPath != null)
                        return MakeResult(explorerPath, "File Explorer");
                }

                // ─── 2. VS Code Family (VS Code, Antigravity IDE, Cursor, Windsurf, etc.) ─
                if (IsVsCodeFamily(processName, windowTitle))
                {
                    // Strategy A: Parse window title (most reliable for foreground editor)
                    var titlePath = TryGetVsCodePathFromTitle(windowTitle, savedPath);
                    if (titlePath != null)
                        return MakeResult(titlePath, $"{processName} (title)");

                    // Strategy B: WMI process command line `--folder-uri` search
                    var cmdPath = TryGetVsCodeFolderByPidOrTree(fgPid, processName);
                    if (cmdPath != null)
                        return MakeResult(cmdPath, $"{processName} (commandline)");

                    // Strategy C: CWD of process / child processes
                    var cwdPath = TryGetWorkingDirectory((int)fgPid);
                    if (cwdPath != null)
                        return MakeResult(cwdPath, $"{processName} (cwd)");
                }

                // ─── 3. Visual Studio ──────────────────────────────
                if (processName.Equals("devenv", StringComparison.OrdinalIgnoreCase))
                {
                    var vsPath = TryGetVisualStudioFolder(fgPid);
                    if (vsPath != null)
                        return MakeResult(vsPath, "Visual Studio");
                }

                // ─── 4. Terminal (Windows Terminal, pwsh, cmd) ─────
                if (processName.Equals("WindowsTerminal", StringComparison.OrdinalIgnoreCase) ||
                    processName.Equals("pwsh", StringComparison.OrdinalIgnoreCase) ||
                    processName.Equals("powershell", StringComparison.OrdinalIgnoreCase) ||
                    processName.Equals("cmd", StringComparison.OrdinalIgnoreCase))
                {
                    var termPath = TryGetTerminalWorkspace(foregroundHwnd, fgPid);
                    if (termPath != null)
                        return MakeResult(termPath, "Terminal");
                }

                Debug.WriteLine($"[WD] Foreground window '{processName}' did not match specific rules; trying title parsing");
                // Generic title match if foreground title contains an IDE suffix
                var genericTitlePath = TryGetVsCodePathFromTitle(windowTitle, savedPath);
                if (genericTitlePath != null)
                    return MakeResult(genericTitlePath, "Generic IDE (title)");
            }

            // ─── Fallback A: Scan all running VS Code family processes ───
            Debug.WriteLine("[WD] Scanning all running IDE processes for active workspaces");
            var scannedVsCode = TryScanAllVsCodeProcesses(savedPath);
            if (scannedVsCode != null)
                return MakeResult(scannedVsCode, "IDE Process Scan");

            var scannedVs = TryGetVisualStudioFolder(0);
            if (scannedVs != null)
                return MakeResult(scannedVs, "Visual Studio Scan");

            // ─── Fallback B: Saved workspace from settings ───────────────
            if (!string.IsNullOrWhiteSpace(savedPath) && Directory.Exists(savedPath))
            {
                Debug.WriteLine($"[WD] Using saved workspace: '{savedPath}'");
                return MakeResult(savedPath, "Saved Settings");
            }

            // ─── Fallback C: Home Directory ─────────────────────────────
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            Debug.WriteLine($"[WD] Fallback to Home: '{home}'");
            return new WorkspaceInfo { Path = home, Method = "Home Directory", ProjectName = "Home" };
        }

        // ────────────────────────────────────────────────────────────────
        //  Helper: Check if process or window title belongs to VS Code family
        // ────────────────────────────────────────────────────────────────

        private static bool IsVsCodeFamily(string processName, string windowTitle)
        {
            if (VsCodeProcessNames.Any(n => processName.Equals(n, StringComparison.OrdinalIgnoreCase)))
                return true;

            if (VsCodeTitleSuffixes.Any(s => windowTitle.EndsWith(s, StringComparison.OrdinalIgnoreCase)))
                return true;

            if (windowTitle.Contains("Antigravity") || windowTitle.Contains("Visual Studio Code") ||
                windowTitle.Contains("Cursor") || windowTitle.Contains("Windsurf"))
                return true;

            return false;
        }

        private static string GetTitle(IntPtr hwnd)
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

        // ────────────────────────────────────────────────────────────────
        //  Result Builder & Project Name Derivation
        // ────────────────────────────────────────────────────────────────

        private static WorkspaceInfo MakeResult(string path, string method)
        {
            var name = DeriveProjectName(path);
            Debug.WriteLine($"[WD] ✓ {method}: '{path}' → ProjectName: '{name}'");
            return new WorkspaceInfo { Path = path, Method = method, ProjectName = name };
        }

        public static string DeriveProjectName(string path)
        {
            if (string.IsNullOrEmpty(path) || !Directory.Exists(path))
                return "Unknown";

            try
            {
                var sln = Directory.GetFiles(path, "*.sln").FirstOrDefault();
                if (sln != null)
                    return System.IO.Path.GetFileNameWithoutExtension(sln);

                var csproj = Directory.GetFiles(path, "*.csproj").FirstOrDefault();
                if (csproj != null)
                    return System.IO.Path.GetFileNameWithoutExtension(csproj);

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
            }
            catch { }

            return new DirectoryInfo(path.TrimEnd('\\', '/')).Name;
        }

        // ────────────────────────────────────────────────────────────────
        //  VS Code Title Parsing Logic
        // ────────────────────────────────────────────────────────────────
        //  Title formats across VS Code variants:
        //    "GAS - Antigravity IDE - ConversationHtml.cs"
        //    "ConversationHtml.cs - GAS - Visual Studio Code"
        //    "GAS - Cursor"
        //    "WorkspaceName - AppName"

        private static string? TryGetVsCodePathFromTitle(string title, string? savedPath)
        {
            if (string.IsNullOrWhiteSpace(title)) return null;

            Debug.WriteLine($"[WD] Parsing title: '{title}'");

            // Remove known IDE suffixes
            string cleanTitle = title;
            foreach (var suffix in VsCodeTitleSuffixes)
            {
                if (cleanTitle.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
                {
                    cleanTitle = cleanTitle[..^suffix.Length];
                    break;
                }
            }

            var parts = cleanTitle.Split(new[] { " - ", " – ", " — " }, StringSplitOptions.RemoveEmptyEntries)
                                  .Select(p => p.Trim())
                                  .Where(p => !string.IsNullOrEmpty(p))
                                  .ToArray();

            if (parts.Length == 0) return null;

            // Collect candidate folder names from the title parts
            var candidateNames = new List<string>();
            foreach (var part in parts)
            {
                // Ignore file names with extensions (e.g. ConversationHtml.cs)
                if (System.IO.Path.HasExtension(part) && !part.EndsWith(".sln") && !part.EndsWith(".csproj"))
                    continue;
                candidateNames.Add(part);
            }

            Debug.WriteLine($"[WD] Title candidates: [{string.Join(", ", candidateNames)}]");

            // 1. Check if savedPath's directory name matches any candidate
            if (!string.IsNullOrWhiteSpace(savedPath) && Directory.Exists(savedPath))
            {
                var savedName = new DirectoryInfo(savedPath.TrimEnd('\\', '/')).Name;
                if (candidateNames.Any(c => c.Equals(savedName, StringComparison.OrdinalIgnoreCase)))
                {
                    Debug.WriteLine($"[WD] Title candidate matched savedPath: '{savedPath}'");
                    return savedPath;
                }
            }

            // 2. Check if current application working directory / base directory matches
            var currentBase = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            // Check up to 3 parent directories of BaseDirectory (e.g. d:\GAS\GAS)
            var checkDir = new DirectoryInfo(currentBase);
            while (checkDir != null)
            {
                if (candidateNames.Any(c => c.Equals(checkDir.Name, StringComparison.OrdinalIgnoreCase)))
                {
                    Debug.WriteLine($"[WD] Title candidate matched workspace hierarchy: '{checkDir.FullName}'");
                    return checkDir.FullName;
                }
                checkDir = checkDir.Parent;
            }

            // 3. Search process command lines for --folder-uri matching candidate names
            var processFolder = TryFindVsCodeProcessFolderMatchingNames(candidateNames);
            if (processFolder != null) return processFolder;

            // 4. Search standard development directory locations on disk
            foreach (var candName in candidateNames)
            {
                var diskMatch = FindFolderOnDiskByName(candName);
                if (diskMatch != null) return diskMatch;
            }

            return null;
        }

        private static string? FindFolderOnDiskByName(string folderName)
        {
            if (string.IsNullOrWhiteSpace(folderName)) return null;

            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var searchRoots = new[]
            {
                @"D:\",
                @"D:\src",
                @"C:\src",
                @"D:\Projects",
                System.IO.Path.Combine(userProfile, "source", "repos"),
                System.IO.Path.Combine(userProfile, "Projects"),
                System.IO.Path.Combine(userProfile, "Documents"),
                @"C:\"
            };

            foreach (var root in searchRoots)
            {
                try
                {
                    if (!Directory.Exists(root)) continue;

                    // Direct child check first
                    var target = System.IO.Path.Combine(root, folderName);
                    if (Directory.Exists(target)) return target;

                    // Check subdirectories (1 level deep)
                    var subdirs = Directory.GetDirectories(root);
                    foreach (var sub in subdirs)
                    {
                        var subTarget = System.IO.Path.Combine(sub, folderName);
                        if (Directory.Exists(subTarget)) return subTarget;
                    }
                }
                catch { }
            }

            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  WMI / Process Command-Line Search
        // ────────────────────────────────────────────────────────────────

        private static string? TryGetVsCodeFolderByPidOrTree(uint targetPid, string processName)
        {
            try
            {
                // Query command line of the target PID first
                if (targetPid > 0)
                {
                    var cmdLine = GetCommandLine((int)targetPid);
                    if (cmdLine != null)
                    {
                        var folder = ExtractFolderFromCommandLine(cmdLine);
                        if (folder != null) return folder;
                    }
                }

                // Query command lines of all processes with matching name
                var procs = Process.GetProcessesByName(processName);
                foreach (var p in procs)
                {
                    try
                    {
                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine != null)
                        {
                            var folder = ExtractFolderFromCommandLine(cmdLine);
                            if (folder != null) return folder;
                        }
                    }
                    catch { }
                    finally { p.Dispose(); }
                }
            }
            catch (Exception ex) { Debug.WriteLine($"[WD] WMI search error: {ex.Message}"); }
            return null;
        }

        private static string? TryFindVsCodeProcessFolderMatchingNames(List<string> candidateNames)
        {
            foreach (var procName in VsCodeProcessNames)
            {
                try
                {
                    var procs = Process.GetProcessesByName(procName);
                    foreach (var p in procs)
                    {
                        try
                        {
                            var cmdLine = GetCommandLine(p.Id);
                            if (cmdLine == null) continue;

                            var folder = ExtractFolderFromCommandLine(cmdLine);
                            if (folder != null)
                            {
                                var dirName = new DirectoryInfo(folder.TrimEnd('\\', '/')).Name;
                                if (candidateNames.Any(c => c.Equals(dirName, StringComparison.OrdinalIgnoreCase)))
                                    return folder;
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

        private static string? TryScanAllVsCodeProcesses(string? savedPath)
        {
            foreach (var procName in VsCodeProcessNames)
            {
                try
                {
                    var procs = Process.GetProcessesByName(procName);
                    foreach (var p in procs)
                    {
                        try
                        {
                            var cmdLine = GetCommandLine(p.Id);
                            if (cmdLine == null) continue;

                            var folder = ExtractFolderFromCommandLine(cmdLine);
                            if (folder != null)
                            {
                                // Prioritize savedPath if it matches
                                if (!string.IsNullOrWhiteSpace(savedPath) &&
                                    folder.Equals(savedPath, StringComparison.OrdinalIgnoreCase))
                                    return folder;

                                return folder;
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

        private static string? ExtractFolderFromCommandLine(string cmdLine)
        {
            if (string.IsNullOrWhiteSpace(cmdLine)) return null;

            // Pattern 1: --folder-uri=file:///d:/GAS/GAS
            var m1 = Regex.Match(cmdLine, @"--folder-uri=file:///([^""\s]+)", RegexOptions.IgnoreCase);
            if (m1.Success)
            {
                var decoded = Uri.UnescapeDataString(m1.Groups[1].Value).Replace('/', '\\');
                if (Directory.Exists(decoded)) return decoded;
            }

            // Pattern 2: --workspace=file:///d:/...
            var m2 = Regex.Match(cmdLine, @"--workspace=file:///([^""\s]+)", RegexOptions.IgnoreCase);
            if (m2.Success)
            {
                var decoded = Uri.UnescapeDataString(m2.Groups[1].Value).Replace('/', '\\');
                var dir = System.IO.Path.GetDirectoryName(decoded);
                if (dir != null && Directory.Exists(dir)) return dir;
            }

            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  File Explorer
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
            catch (Exception ex) { Debug.WriteLine($"[WD] Shell COM error: {ex.Message}"); }
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
        //  Terminal
        // ────────────────────────────────────────────────────────────────

        private static string? TryGetTerminalWorkspace(IntPtr hwnd, uint pid)
        {
            try
            {
                var title = GetTitle(hwnd);
                if (!string.IsNullOrEmpty(title))
                {
                    var m = Regex.Match(title, @"([A-Z]:\\[^\s>|]+)", RegexOptions.IgnoreCase);
                    if (m.Success && Directory.Exists(m.Value))
                        return m.Value;
                }

                var cwd = TryGetWorkingDirectory((int)pid);
                if (cwd != null) return cwd;
            }
            catch { }
            return null;
        }

        // ────────────────────────────────────────────────────────────────
        //  Process WMI Helpers
        // ────────────────────────────────────────────────────────────────

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
