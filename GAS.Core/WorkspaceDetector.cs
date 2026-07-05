using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace GAS.Core
{
    /// <summary>
    /// Detects the current workspace directory using a priority chain:
    /// 1. Saved LastWorkspacePath from settings (if directory still exists)
    /// 2. Active VS Code window folder (via process command line)
    /// 3. Active Visual Studio solution directory (via process command line)
    /// 4. User home directory as final fallback
    /// </summary>
    public static class WorkspaceDetector
    {
        /// <summary>
        /// Returns the best workspace path available.
        /// Pass the saved LastWorkspacePath from settings (or null/empty).
        /// </summary>
        public static string Detect(string? savedPath)
        {
            // 1. Use the saved path if it still exists on disk
            if (!string.IsNullOrWhiteSpace(savedPath) && Directory.Exists(savedPath))
                return savedPath;

            // 2. Try VS Code
            var vsCodePath = TryGetVsCodeFolder();
            if (vsCodePath != null)
                return vsCodePath;

            // 3. Try Visual Studio
            var vsPath = TryGetVisualStudioFolder();
            if (vsPath != null)
                return vsPath;

            // 4. Fall back to user home directory
            return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        private static string? TryGetVsCodeFolder()
        {
            try
            {
                var codeProcesses = Process.GetProcessesByName("Code");
                foreach (var p in codeProcesses)
                {
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

        private static string? TryGetVisualStudioFolder()
        {
            try
            {
                var vsProcesses = Process.GetProcessesByName("devenv");
                foreach (var p in vsProcesses)
                {
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
