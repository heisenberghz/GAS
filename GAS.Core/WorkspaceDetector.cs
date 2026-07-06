using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace GAS.Core
{
    /// <summary>
    /// Detects the current workspace directory using a priority chain:
    /// 1. The foreground window's folder (File Explorer, VS Code, Visual Studio)
    /// 2. Saved LastWorkspacePath from settings (if directory still exists)
    /// 3. User home directory as final fallback
    /// </summary>
    public class WorkspaceInfo
    {
        public string Path { get; set; } = string.Empty;
        public string Method { get; set; } = string.Empty;
    }

    public static class WorkspaceDetector
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);

        /// <summary>
        /// Returns the best workspace path available.
        /// <param name="savedPath">Saved LastWorkspacePath from settings (or null/empty).</param>
        /// <param name="foregroundHwnd">The HWND of the foreground window captured at hotkey time.</param>
        /// </summary>
        public static WorkspaceInfo Detect(string? savedPath, IntPtr foregroundHwnd = default)
        {
            System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Detect called. foregroundHwnd={foregroundHwnd}, savedPath={savedPath}");

            if (foregroundHwnd != IntPtr.Zero)
            {
                // Identify what process owns this HWND
                GetWindowThreadProcessId(foregroundHwnd, out uint fgPid);
                string processName = "";
                try
                {
                    var proc = Process.GetProcessById((int)fgPid);
                    processName = proc.ProcessName;
                    proc.Dispose();
                }
                catch { }

                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Foreground PID={fgPid}, ProcessName={processName}");

                // 1a. Try File Explorer — match by exact HWND
                if (string.Equals(processName, "explorer", StringComparison.OrdinalIgnoreCase))
                {
#pragma warning disable CA1416
                    var explorerPath = TryGetFileExplorerFolderByHwnd(foregroundHwnd);
#pragma warning restore CA1416
                    if (explorerPath != null)
                    {
                        System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] ✓ Found via File Explorer (HWND match): {explorerPath}");
                        return new WorkspaceInfo { Path = explorerPath, Method = "File Explorer" };
                    }
                    System.Diagnostics.Debug.WriteLine("[WorkspaceDetector] ✗ File Explorer HWND match failed");
                }

                // 1b. Try VS Code — match by process ID
                if (string.Equals(processName, "Code", StringComparison.OrdinalIgnoreCase))
                {
                    var vsCodePath = TryGetVsCodeFolderByPid(fgPid);
                    if (vsCodePath != null)
                    {
                        System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] ✓ Found via VS Code (PID match): {vsCodePath}");
                        return new WorkspaceInfo { Path = vsCodePath, Method = "VS Code" };
                    }
                    System.Diagnostics.Debug.WriteLine("[WorkspaceDetector] ✗ VS Code PID match failed");
                }

                // 1c. Try Visual Studio — match by process ID
                if (string.Equals(processName, "devenv", StringComparison.OrdinalIgnoreCase))
                {
                    var vsPath = TryGetVisualStudioFolderByPid(fgPid);
                    if (vsPath != null)
                    {
                        System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] ✓ Found via Visual Studio (PID match): {vsPath}");
                        return new WorkspaceInfo { Path = vsPath, Method = "Visual Studio" };
                    }
                    System.Diagnostics.Debug.WriteLine("[WorkspaceDetector] ✗ Visual Studio PID match failed");
                }

                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Foreground process '{processName}' is not a recognized workspace host");
            }

            // 2. Fallback: scan all processes (no HWND was available)
            System.Diagnostics.Debug.WriteLine("[WorkspaceDetector] Falling back to scan-all-processes mode");

            var anyVsCode = TryGetVsCodeFolderByPid(0);
            if (anyVsCode != null)
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] ✓ Found via VS Code (scan-all): {anyVsCode}");
                return new WorkspaceInfo { Path = anyVsCode, Method = "VS Code" };
            }

            var anyVs = TryGetVisualStudioFolderByPid(0);
            if (anyVs != null)
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] ✓ Found via Visual Studio (scan-all): {anyVs}");
                return new WorkspaceInfo { Path = anyVs, Method = "Visual Studio" };
            }

            // 3. Use saved path
            if (!string.IsNullOrWhiteSpace(savedPath) && Directory.Exists(savedPath))
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] ✓ Found via Saved Settings: {savedPath}");
                return new WorkspaceInfo { Path = savedPath, Method = "Saved Settings" };
            }

            // 4. Home directory
            var fallback = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] ✓ Fallback to Home Directory: {fallback}");
            return new WorkspaceInfo { Path = fallback, Method = "Home Directory" };
        }

        // ────────────────────────────────────────────────────────────────
        // File Explorer: match by exact HWND via Shell COM
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

                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Shell.Application returned {count} windows. Target HWND={targetHwnd}");

                for (int i = 0; i < count; i++)
                {
                    try
                    {
                        object? window = windows.GetType().InvokeMember("Item",
                            System.Reflection.BindingFlags.InvokeMethod, null, windows, new object[] { i });
                        if (window == null) continue;

                        // Get this window's HWND
                        var hwndObj = window.GetType().InvokeMember("HWND",
                            System.Reflection.BindingFlags.GetProperty, null, window, null);
                        IntPtr windowHwnd = new IntPtr(Convert.ToInt64(hwndObj));

                        System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector]   Window[{i}] HWND={windowHwnd}");

                        // Only match the exact foreground window
                        if (windowHwnd != targetHwnd) continue;

                        System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector]   → HWND matched!");

                        // Extract the folder path
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

                        System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector]   → Path resolved to: {path}");

                        if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path))
                            return path;
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector]   Window[{i}] error: {ex.Message}");
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[WorkspaceDetector] Shell COM error: {ex.Message}");
            }
            return null;
        }

        // ────────────────────────────────────────────────────────────────
        // VS Code: match by PID (each VS Code instance is a separate process tree)
        // ────────────────────────────────────────────────────────────────

        private static string? TryGetVsCodeFolderByPid(uint targetPid)
        {
            try
            {
                var codeProcesses = Process.GetProcessesByName("Code");
                foreach (var p in codeProcesses)
                {
                    try
                    {
                        // When targetPid > 0, only check the specific process tree
                        // VS Code's foreground PID is the main window process; its child
                        // renderer processes carry the --folder-uri arg. We need to scan
                        // all Code processes but look for the one whose parent matches.
                        // However, the simplest reliable approach: if targetPid > 0, get
                        // the workspace from the *specific* process first, then fall back
                        // to scanning all processes for the folder-uri.

                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine == null) continue;

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

        // ────────────────────────────────────────────────────────────────
        // Visual Studio: match by PID (each VS instance is a separate devenv.exe)
        // ────────────────────────────────────────────────────────────────

        private static string? TryGetVisualStudioFolderByPid(uint targetPid)
        {
            try
            {
                var vsProcesses = Process.GetProcessesByName("devenv");
                foreach (var p in vsProcesses)
                {
                    if (targetPid > 0 && p.Id != (int)targetPid) continue;
                    try
                    {
                        var cmdLine = GetCommandLine(p.Id);
                        if (cmdLine != null)
                        {
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

        // ────────────────────────────────────────────────────────────────

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

