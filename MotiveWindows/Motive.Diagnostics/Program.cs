using System;
using System.IO;
using System.Threading.Tasks;
using Motive.Core;

namespace Motive.Diagnostics
{
    class Program
    {
        static async Task Main(string[] args)
        {
            Console.WriteLine("==================================================");
            Console.WriteLine("Motive Windows Port - Phase 1 Diagnostics Launcher");
            Console.WriteLine("==================================================");

            // 1. Resolve Binary
            Console.WriteLine("\n[1/3] Resolving OpenCode CLI Binary...");
            var binaryManager = new BinaryManager();
            var (binaryPath, error) = binaryManager.ResolveBinary();

            if (binaryPath == null)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"Error: {error}");
                Console.ResetColor();
                Console.WriteLine("\nTo continue, please install the OpenCode CLI globally:");
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("  npm install -g opencode-ai");
                Console.ResetColor();
                Console.WriteLine("\nOr place a mock 'opencode.exe' (size > 1MB) in the application output directory.");
                Console.WriteLine("\nPress ENTER to exit...");
                Console.ReadLine();
                return;
            }

            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"Success: Found binary at:\n -> {binaryPath}");
            Console.ResetColor();

            // 2. Start OpenCodeServer
            Console.WriteLine("\n[2/3] Starting OpenCode Background Server...");
            using (var server = new OpenCodeServer())
            {
                server.ServerUrlDetected += (url) =>
                {
                    Console.ForegroundColor = ConsoleColor.Cyan;
                    Console.WriteLine($"[Event] Server URL Detected: {url}");
                    Console.ResetColor();
                };

                server.OutputReceived += (line) =>
                {
                    Console.WriteLine($"[Server Stdout] {line}");
                };

                server.ErrorReceived += (line) =>
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine($"[Server Stderr] {line}");
                    Console.ResetColor();
                };

                server.ProcessExited += (exitCode) =>
                {
                    Console.ForegroundColor = ConsoleColor.DarkYellow;
                    Console.WriteLine($"[Event] Process exited with code {exitCode}");
                    Console.ResetColor();
                };

                try
                {
                    var workingDirectory = AppDomain.CurrentDomain.BaseDirectory;
                    Console.WriteLine("Spawning process...");
                    
                    var serverUrl = await server.StartAsync(binaryPath, workingDirectory);
                    
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine($"\nServer is running at: {serverUrl}");
                    Console.ResetColor();

                    // 3. Perform Health Check
                    Console.WriteLine("\n[3/3] Performing Health Check...");
                    var isHealthy = await server.CheckHealthAsync();
                    if (isHealthy)
                    {
                        Console.ForegroundColor = ConsoleColor.Green;
                        Console.WriteLine("Success: Health check PASSED!");
                        Console.ResetColor();
                    }
                    else
                    {
                        Console.ForegroundColor = ConsoleColor.Red;
                        Console.WriteLine("Warning: Health check FAILED (but process is running).");
                        Console.ResetColor();
                    }

                    Console.WriteLine("\nPress ENTER to shut down the server gracefully...");
                    Console.ReadLine();

                    Console.WriteLine("Stopping server...");
                    await server.StopAsync();
                    Console.WriteLine("Server stopped successfully.");
                }
                catch (Exception ex)
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine($"Error occurred: {ex.Message}");
                    if (ex.InnerException != null)
                    {
                        Console.WriteLine($"Inner Error: {ex.InnerException.Message}");
                    }
                    Console.ResetColor();
                }
            }

            Console.WriteLine("\nDiagnostics run finished. Press ENTER to exit...");
            Console.ReadLine();
        }
    }
}
