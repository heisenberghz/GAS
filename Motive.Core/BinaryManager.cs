using System;
using System.IO;
using System.Linq;

namespace Motive.Core
{
    public class BinaryManager
    {
        private const long MinimumBinarySize = 1_000_000; // ~1MB for raw exe
        private readonly string _customSourcePath;

        public BinaryManager(string customSourcePath = "")
        {
            _customSourcePath = customSourcePath;
        }

        /// <summary>
        /// Gets the standard local application workspace directory: %USERPROFILE%\.motive
        /// </summary>
        public static string WorkspaceDirectory
        {
            get
            {
                var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                return Path.Combine(home, ".motive");
            }
        }

        /// <summary>
        /// Gets the local app data support directory: %APPDATA%\Motive
        /// </summary>
        public static string AppSupportDirectory
        {
            get
            {
                var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                return Path.Combine(appData, "Motive");
            }
        }

        /// <summary>
        /// Gets the runtime support directory (e.g. %APPDATA%\Motive\runtime)
        /// </summary>
        public static string RuntimeDirectory => Path.Combine(AppSupportDirectory, "runtime");

        /// <summary>
        /// Resolves the path to the opencode binary on Windows.
        /// Checks custom paths, bundled paths, system PATH, and global npm paths.
        /// </summary>
        /// <returns>A tuple with the resolved absolute path and an error message if not found.</returns>
        private (string? Path, string? Error) InternalResolveBinary()
        {
            // 1. Check custom path if provided
            if (!string.IsNullOrWhiteSpace(_customSourcePath) && File.Exists(_customSourcePath))
            {
                if (IsValidBinary(_customSourcePath))
                {
                    return (_customSourcePath, null);
                }
            }

            // 2. Check App Support directory (where we might copy/save a downloaded/signed binary)
            var appSupportBinary = Path.Combine(AppSupportDirectory, "opencode.exe");
            if (File.Exists(appSupportBinary) && IsValidBinary(appSupportBinary))
            {
                return (appSupportBinary, null);
            }

            // 3. Check App folder (Bundled)
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var bundledPaths = new[]
            {
                Path.Combine(baseDir, "opencode.exe"),
                Path.Combine(baseDir, "Resources", "opencode.exe")
            };

            foreach (var path in bundledPaths)
            {
                if (File.Exists(path) && IsValidBinary(path))
                {
                    return (path, null);
                }
            }

            // 4. Check system PATH
            var envPath = Environment.GetEnvironmentVariable("PATH") ?? "";
            var pathDirs = envPath.Split(Path.PathSeparator)
                                  .Select(d => d.Trim())
                                  .Where(d => !string.IsNullOrEmpty(d));

            foreach (var dir in pathDirs)
            {
                // On Windows, it could be either opencode.exe (compiled binary) or opencode.cmd (npm wrapper)
                var exePath = Path.Combine(dir, "opencode.exe");
                if (File.Exists(exePath) && IsValidBinary(exePath))
                {
                    return (exePath, null);
                }

                var cmdPath = Path.Combine(dir, "opencode.cmd");
                if (File.Exists(cmdPath) && IsValidBinary(cmdPath))
                {
                    return (cmdPath, null);
                }
            }

            // 5. Check global npm installation folders directly
            var appDataRoaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData); // Roaming AppData
            var npmGlobalDir = Path.Combine(appDataRoaming, "npm");
            
            var directNpmCmd = Path.Combine(npmGlobalDir, "opencode.cmd");
            if (File.Exists(directNpmCmd) && IsValidBinary(directNpmCmd))
            {
                return (directNpmCmd, null);
            }

            // Direct check in global node_modules for win32 binary
            var globalNodeModules = Path.Combine(npmGlobalDir, "node_modules");
            var win32BinaryDir = Path.Combine(globalNodeModules, "opencode-ai", "node_modules", "opencode-win32-x64", "bin", "opencode.exe");
            if (File.Exists(win32BinaryDir) && IsValidBinary(win32BinaryDir))
            {
                return (win32BinaryDir, null);
            }

            // 6. Check NVM versions if NVM is installed
            var nvmHome = Environment.GetEnvironmentVariable("NVM_HOME");
            if (!string.IsNullOrEmpty(nvmHome) && Directory.Exists(nvmHome))
            {
                try
                {
                    // Scan subdirectories for versions
                    foreach (var nodeDir in Directory.GetDirectories(nvmHome))
                    {
                        var nvmPlatformPath = Path.Combine(nodeDir, "node_modules", "opencode-ai", "node_modules", "opencode-win32-x64", "bin", "opencode.exe");
                        if (File.Exists(nvmPlatformPath) && IsValidBinary(nvmPlatformPath))
                        {
                            return (nvmPlatformPath, null);
                        }

                        var nvmShimPath = Path.Combine(nodeDir, "opencode.cmd");
                        if (File.Exists(nvmShimPath) && IsValidBinary(nvmShimPath))
                        {
                            return (nvmShimPath, null);
                        }
                    }
                }
                catch
                {
                    // Ignore directory read errors
                }
            }

            return (null, "OpenCode CLI not found. Install via npm: npm install -g opencode-ai");
        }

        /// <summary>
        /// Public wrapper to resolve binary and resolve cmd wrappers into native exe files.
        /// </summary>
        public (string? Path, string? Error) ResolveBinary()
        {
            var (path, error) = InternalResolveBinary();
            if (path != null)
            {
                return (GetDirectExePath(path), null);
            }
            return (null, error);
        }

        private string GetDirectExePath(string cmdPath)
        {
            if (string.IsNullOrEmpty(cmdPath) || !cmdPath.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase))
            {
                return cmdPath;
            }

            var dir = Path.GetDirectoryName(cmdPath);
            if (string.IsNullOrEmpty(dir)) return cmdPath;

            var candidates = new[]
            {
                Path.Combine(dir, "node_modules", "opencode-ai", "bin", "opencode.exe"),
                Path.Combine(dir, "node_modules", "opencode-ai", "node_modules", "opencode-win32-x64", "bin", "opencode.exe")
            };

            foreach (var candidate in candidates)
            {
                if (File.Exists(candidate) && IsValidBinary(candidate))
                {
                    return candidate;
                }
            }

            return cmdPath;
        }

        /// <summary>
        /// Validates if a file is a valid binary.
        /// For .exe files, checks if the size is >= 1MB to filter out invalid stubs.
        /// For script wrappers (.cmd, .bat, .ps1), verifies that it contains data.
        /// </summary>
        public static bool IsValidBinary(string path)
        {
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                return false;
            }

            try
            {
                var fileInfo = new FileInfo(path);
                var extension = fileInfo.Extension.ToLowerInvariant();

                if (extension == ".exe")
                {
                    return fileInfo.Length >= MinimumBinarySize;
                }

                // If it is an npm command wrapper or batch script, it's small, so we just check if it's not empty
                if (extension == ".cmd" || extension == ".bat" || extension == ".ps1")
                {
                    return fileInfo.Length > 0;
                }

                // Default fallback
                return fileInfo.Length > 0;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// Import external binary to App Support folder (equivalent to macOS copy-and-sign)
        /// </summary>
        public void ImportBinary(string sourcePath)
        {
            if (!File.Exists(sourcePath))
            {
                throw new FileNotFoundException("Source binary not found", sourcePath);
            }

            // Ensure destination folder exists
            if (!Directory.Exists(AppSupportDirectory))
            {
                Directory.CreateDirectory(AppSupportDirectory);
            }

            var destPath = Path.Combine(AppSupportDirectory, "opencode.exe");
            
            // Delete if exists
            if (File.Exists(destPath))
            {
                File.Delete(destPath);
            }

            // Copy file (on Windows, no signing step like macOS codesign is needed for local running)
            File.Copy(sourcePath, destPath, true);
        }
    }
}
