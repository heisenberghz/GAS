using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace GAS.Core
{
    public class OpenCodeServer : IDisposable
    {
        private Process? _process;
        private JobObject? _jobObject;
        private Task? _stdoutReadTask;
        private CancellationTokenSource? _cts;
        private readonly object _lock = new object();

        public string? ServerUrl { get; private set; }
        public bool IsRunning => _process != null && !_process.HasExited;

        public event Action<string>? ServerUrlDetected;
        public event Action<string>? OutputReceived;
        public event Action<string>? ErrorReceived;
        public event Action<int>? ProcessExited;

        public async Task<string?> StartAsync(string binaryPath, string workingDirectory, Dictionary<string, string>? environment = null)
        {
            if (IsRunning)
            {
                return ServerUrl;
            }

            if (!File.Exists(binaryPath))
            {
                throw new FileNotFoundException("OpenCode binary not found", binaryPath);
            }

            _cts = new CancellationTokenSource();
            _jobObject = new JobObject();

            var startInfo = new ProcessStartInfo
            {
                FileName = binaryPath,
                Arguments = "serve --port 0 --hostname 127.0.0.1",
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            // Setup environment
            if (environment != null)
            {
                foreach (var kvp in environment)
                {
                    startInfo.EnvironmentVariables[kvp.Key] = kvp.Value;
                }
            }
            if (!startInfo.EnvironmentVariables.ContainsKey("TERM"))
            {
                startInfo.EnvironmentVariables["TERM"] = "dumb";
            }

            _process = new Process { StartInfo = startInfo };
            _process.EnableRaisingEvents = true;
            _process.Exited += OnProcessExited;

            var tcs = new TaskCompletionSource<string>();

            // Start the process
            if (!_process.Start())
            {
                throw new InvalidOperationException("Failed to start OpenCode process.");
            }

            // Bind process to job object immediately to prevent leaks on crash
            _jobObject.AddProcess(_process);

            // Read stdout in background and wait for port detection
            var currentProc = _process;
            var currentJob = _jobObject;
            if (currentProc != null && currentJob != null)
            {
                _stdoutReadTask = Task.Run(async () =>
                {
                    using (var reader = currentProc.StandardOutput)
                    {
                        string? line;
                        while ((line = await reader.ReadLineAsync().ConfigureAwait(false)) != null)
                        {
                            OutputReceived?.Invoke(line);
                            
                            var detectedUrl = ParseListeningUrl(line);
                            if (detectedUrl != null && ServerUrl == null)
                            {
                                lock (_lock)
                                {
                                    if (ServerUrl == null)
                                    {
                                        ServerUrl = detectedUrl;
                                        ServerUrlDetected?.Invoke(detectedUrl);
                                        tcs.TrySetResult(detectedUrl);
                                    }
                                }
                            }
                        }
                    }
                });
            }

            // Start standard error reading task
            if (currentProc != null)
            {
                _ = Task.Run(async () =>
                {
                    using (var reader = currentProc.StandardError)
                    {
                        string? line;
                        while ((line = await reader.ReadLineAsync().ConfigureAwait(false)) != null)
                        {
                            ErrorReceived?.Invoke(line);
                        }
                    }
                });
            }

            // Set up a timeout for port detection (15 seconds)
            var timeoutTask = Task.Delay(TimeSpan.FromSeconds(15), _cts.Token);
            var completedTask = await Task.WhenAny(tcs.Task, timeoutTask).ConfigureAwait(false);

            if (completedTask == timeoutTask)
            {
                await StopAsync().ConfigureAwait(false);
                throw new TimeoutException("Timed out waiting for OpenCode server to report its port.");
            }

            return await tcs.Task.ConfigureAwait(false);
        }

        private void OnProcessExited(object? sender, EventArgs e)
        {
            int exitCode = -1;
            try
            {
                exitCode = _process?.ExitCode ?? -1;
            }
            catch
            {
                // Process properties might be inaccessible
            }

            CleanUpProcess();
            ProcessExited?.Invoke(exitCode);
        }

        private void CleanUpProcess()
        {
            lock (_lock)
            {
                _cts?.Cancel();
                _cts?.Dispose();
                _cts = null;

                _process?.Dispose();
                _process = null;

                _jobObject?.Dispose();
                _jobObject = null;

                ServerUrl = null;
            }
        }

        public async Task StopAsync()
        {
            Process? processToStop;
            lock (_lock)
            {
                processToStop = _process;
            }

            if (processToStop != null && !processToStop.HasExited)
            {
                try
                {
                    // Kill process (Windows handles this cleanly, job object also takes care of sub-processes)
                    processToStop.Kill();
                    
                    // Wait up to 2 seconds for exit
                    int waitMs = 0;
                    while (!processToStop.HasExited && waitMs < 2000)
                    {
                        await Task.Delay(100).ConfigureAwait(false);
                        waitMs += 100;
                    }
                }
                catch
                {
                    // Ignore errors during kill
                }
            }

            CleanUpProcess();
        }

        /// <summary>
        /// Perform an HTTP health check on the background server
        /// </summary>
        public async Task<bool> CheckHealthAsync()
        {
            var url = ServerUrl;
            if (string.IsNullOrEmpty(url)) return false;

            using (var client = new HttpClient())
            {
                client.Timeout = TimeSpan.FromSeconds(5);
                try
                {
                    // OpenCode serve has a GET /session endpoint for sessions
                    var response = await client.GetAsync($"{url}/session").ConfigureAwait(false);
                    int statusCode = (int)response.StatusCode;
                    return statusCode >= 200 && statusCode < 500;
                }
                catch
                {
                    return false;
                }
            }
        }

        /// <summary>
        /// Parses the output lines looking for: "listening on http://127.0.0.1:4096"
        /// </summary>
        public static string? ParseListeningUrl(string? line)
        {
            if (string.IsNullOrEmpty(line)) return null;
            var lowered = line.ToLowerInvariant();
            if (!lowered.Contains("listening")) return null;

            var patterns = new[] { "http://127.0.0.1:", "http://localhost:", "http://0.0.0.0:" };
            foreach (var pattern in patterns)
            {
                int index = lowered.IndexOf(pattern, StringComparison.Ordinal);
                if (index != -1)
                {
                    int afterPatternIndex = index + pattern.Length;
                    int length = 0;
                    while (afterPatternIndex + length < line.Length && char.IsDigit(line[afterPatternIndex + length]))
                    {
                        length++;
                    }
                    if (length > 0 && int.TryParse(line.Substring(afterPatternIndex, length), out int port) && port > 0)
                    {
                        return $"http://127.0.0.1:{port}";
                    }
                }
            }
            return null;
        }

        public void Dispose()
        {
            StopAsync().GetAwaiter().GetResult();
        }
    }
}

