using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace GAS.Core
{
    /// <summary>
    /// Detects the current workspace directory using a priority chain:
    /// 1. Active VS Code window folder (via process command line)
    /// 2. Active Visual Studio solution directory (via process command line)
    /// 3. Saved LastWorkspacePath from settings (if directory still exists)
    /// 4. User home directory as final fallback
    /// </summary>
    public class WorkspaceInfo
    {
        public string Path { get; set; } = string.Empty;
        public string Method { get; set; } = string.Empty;
    }

    public static class WorkspaceDetector
    {
        public static WorkspaceInfo Detect(string? savedPath, uint targetProcessId = 0)
        {
            var vsCodePath = TryGetVsCodeFolder(targetProcessId);
            if (vsCodePath != null)
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Found via VS Code: {vsCodePath}");
                return new WorkspaceInfo { Path = vsCodePath, Method = "VS Code" };
            }

            var vsPath = TryGetVisualStudioFolder(targetProcessId);
            if (vsPath != null)
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Found via Visual Studio: {vsPath}");
                return new WorkspaceInfo { Path = vsPath, Method = "Visual Studio" };
            }

#pragma warning disable CA1416
            var explorerPath = TryGetFileExplorerFolder(targetProcessId);
            if (explorerPath != null)
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Found via File Explorer: {explorerPath}");
                return new WorkspaceInfo { Path = explorerPath, Method = "File Explorer" };
            }
#pragma warning restore CA1416

            if (!string.IsNullOrWhiteSpace(savedPath) && Directory.Exists(savedPath))
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Found via Saved Settings: {savedPath}");
                return new WorkspaceInfo { Path = savedPath, Method = "Saved Settings" };
            }

            var fallback = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Fallback to Home Directory: {fallback}");
            return new WorkspaceInfo { Path = fallback, Method = "Home Directory" };
        }

        private static string? TryGetVsCodeFolder(uint targetProcessId)
        {
            try
            {
                var codeProcesses = Process.GetProcessesByName("Code");
                foreach (var p in codeProcesses)
                {
                    if (targetProcessId > 0 && p.Id != targetProcessId) continue;
                    try
                    {
                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine == null) continue;

                        // VS Code passes --folder-uri=file:///C:/path to its renderer processes
                        var match = Regex.Match(cmdLine, @"--folder-uri=file:///([^""''\s]+)", RegexOptions.IgnoreCase);
                        if (match.Success)
                        {
                            var rawPath = match.Groups[1].Value;
                            var decoded = Uri.UnescapeDataString(rawPath).Replace('/', '\\');
                            if (Directory.Exists(decoded))
                                return decoded;
                        }
                    }
                    catch { /* skip inaccessible process */ }
                    finally { p.Dispose(); }
                }
            }
            catch { /* WMI unavailable or access denied */ }
            return null;
        }

        private static string? TryGetVisualStudioFolder(uint targetProcessId)
        {
            try
            {
                var vsProcesses = Process.GetProcessesByName("devenv");
                foreach (var p in vsProcesses)
                {
                    if (targetProcessId > 0 && p.Id != targetProcessId) continue;
                    try
                    {
                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine != null)
                        {
                            // devenv.exe is called with the .sln path as its argument
                            var slnMatch = Regex.Match(cmdLine, "\"([^\"]+\\.sln)\"", RegexOptions.IgnoreCase);
                            if (slnMatch.Success)
                            {
                                var dir = Path.GetDirectoryName(slnMatch.Groups[1].Value);
                                if (dir != null && Directory.Exists(dir))
                                    return dir;
                            }
                        }
                    }
                    catch { /* skip inaccessible process */ }
                    finally { p.Dispose(); }
                }
            }
            catch { /* access denied */ }
            return null;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [System.Runtime.Versioning.SupportedOSPlatform("windows")]
        private static string? TryGetFileExplorerFolder(uint targetProcessId)
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

                        if (targetProcessId > 0)
                        {
                            var hwndObj = window.GetType().InvokeMember("HWND", System.Reflection.BindingFlags.GetProperty, null, window, null);
                            if (hwndObj is long hwndLong || hwndObj is int hwndInt) // Usually long on 64-bit
                            {
                                IntPtr hwnd = new IntPtr(Convert.ToInt64(hwndObj));
                                GetWindowThreadProcessId(hwnd, out uint pid);
                                if (pid != targetProcessId) continue;
                            }
                        }

                        string? name = window.GetType().InvokeMember("Name", System.Reflection.BindingFlags.GetProperty, null, window, null) as string;
                        if (name == "File Explorer" || name == "Windows Explorer")
                        {
                            object? document = window.GetType().InvokeMember("Document", System.Reflection.BindingFlags.GetProperty, null, window, null);
                            if (document != null)
                            {
                                object? folder = document.GetType().InvokeMember("Folder", System.Reflection.BindingFlags.GetProperty, null, document, null);
                                if (folder != null)
                                {
                                    object? self = folder.GetType().InvokeMember("Self", System.Reflection.BindingFlags.GetProperty, null, folder, null);
                                    if (self != null)
                                    {
                                        string? path = self.GetType().InvokeMember("Path", System.Reflection.BindingFlags.GetProperty, null, self, null) as string;
                                        if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path))
                                        {
                                            return path;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    catch { /* Skip window if access fails */ }
                }
            }
            catch { /* COM not available */ }
            return null;
        }

        /// <summary>
        /// Reads the full command line of a process via WMI.
        /// Returns null if access is denied or WMI is unavailable.
        /// </summary>
        private static string? GetCommandLine(int pid)
        {
            try
            {
                using var searcher = new System.Management.ManagementObjectSearcher(
                    $"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {pid}");
                foreach (System.Management.ManagementObject obj in searcher.Get())
                {
                    return obj["CommandLine"]?.ToString();
                }
            }
            catch { /* WMI not available */ }
            return null;
        }
    }
}
