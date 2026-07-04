using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using GAS.Core;
using GAS.Core.Data;
using GAS.Core.Models;

namespace GAS.Diagnostics
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    class Program
    {
        static async Task Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "--clear")
            {
                var store = new CredentialStore();
                store.Delete("OpenAiApiKey");
                store.Delete("AnthropicApiKey");
                Console.WriteLine("Successfully cleared secure API keys from Credential Store.");
                return;
            }

            Console.WriteLine("==================================================");
            Console.WriteLine("GAS Windows Port - Diagnostics Launcher");
            Console.WriteLine("==================================================");

            // ==========================================
            // PHASE 2 DIAGNOSTICS: SECURE STORAGE & DB
            // ==========================================
            Console.WriteLine("\n[Phase 2] Testing Credential Store (DPAPI)...");
            try
            {
                var store = new CredentialStore();
                store.Write("TestApiKey", "sk-anthropic-xyz-12345");
                var key = store.Read("TestApiKey");
                if (key == "sk-anthropic-xyz-12345")
                {
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("Success: Credential Store decrypted key correctly!");
                    Console.ResetColor();
                }
                else
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("Error: Credential key mismatch!");
                    Console.ResetColor();
                }
                store.Delete("TestApiKey");
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"Credential Store failed: {ex.Message}");
                Console.ResetColor();
            }

            Console.WriteLine("\n[Phase 5B] Testing Settings Manager (JSON)...");
            try
            {
                var originalSettings = SettingsManager.Load();
                
                var testSettings = new AppSettings
                {
                    StartOnBoot = true,
                    CustomBinaryPath = @"C:\Custom\opencode.exe",
                    CtrlModifier = true,
                    ShiftModifier = false,
                    AltModifier = true,
                    HotkeyKey = "M"
                };

                SettingsManager.Save(testSettings);

                var reloadedSettings = SettingsManager.Load();
                if (reloadedSettings.StartOnBoot == testSettings.StartOnBoot &&
                    reloadedSettings.CustomBinaryPath == testSettings.CustomBinaryPath &&
                    reloadedSettings.CtrlModifier == testSettings.CtrlModifier &&
                    reloadedSettings.ShiftModifier == testSettings.ShiftModifier &&
                    reloadedSettings.AltModifier == testSettings.AltModifier &&
                    reloadedSettings.HotkeyKey == testSettings.HotkeyKey)
                {
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("Success: SettingsManager saved and reloaded settings correctly!");
                    Console.ResetColor();
                }
                else
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("Error: Loaded settings do not match saved settings!");
                    Console.ResetColor();
                }

                // Restore original settings
                SettingsManager.Save(originalSettings);
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"SettingsManager test failed: {ex.Message}");
                Console.ResetColor();
            }

            Console.WriteLine("\n[Phase 2] Testing Database Persistence (EF Core SQLite)...");
            try
            {
                using (var db = new GASDbContext())
                {
                    // Ensure database and schema are created
                    db.Database.EnsureCreated();
                    Console.WriteLine("Database file initialized successfully.");

                    // Clear old diagnostics data to run cleanly
                    db.Sessions.RemoveRange(db.Sessions);
                    db.SaveChanges();

                    // Insert Session & LogEntries
                    var session = new Session
                    {
                        Intent = "Refactor GAS build scripts",
                        Status = SessionStatus.Running,
                        ProjectPath = @"D:\GAS windows"
                    };

                    session.Logs.Add(new LogEntry { RawJson = "{}", Kind = "ProcessInfo" });
                    session.Logs.Add(new LogEntry { RawJson = "{}", Kind = "ToolCall" });

                    db.Sessions.Add(session);
                    db.SaveChanges();

                    Console.WriteLine("Inserted test Session and LogEntries.");

                    // Query and verify
                    var retrieved = await db.Sessions
                        .Include(s => s.Logs)
                        .FirstOrDefaultAsync(s => s.Id == session.Id);

                    if (retrieved != null && retrieved.Logs.Count == 2)
                    {
                        Console.ForegroundColor = ConsoleColor.Green;
                        Console.WriteLine($"Success: Database retrieved Session (Id={retrieved.Id}) with {retrieved.Logs.Count} logs.");
                        Console.ResetColor();
                    }
                    else
                    {
                        Console.ForegroundColor = ConsoleColor.Red;
                        Console.WriteLine("Error: Failed to retrieve session or logs.");
                        Console.ResetColor();
                    }

                    // Cascade delete test
                    db.Sessions.Remove(session);
                    db.SaveChanges();

                    var logCount = await db.LogEntries.CountAsync();
                    if (logCount == 0)
                    {
                        Console.ForegroundColor = ConsoleColor.Green;
                        Console.WriteLine("Success: Database Cascade Delete verified (all logs wiped)!");
                        Console.ResetColor();
                    }
                    else
                    {
                        Console.ForegroundColor = ConsoleColor.Red;
                        Console.WriteLine($"Error: Cascade delete failed, {logCount} logs remain.");
                        Console.ResetColor();
                    }
                }
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"Database test failed: {ex.Message}");
                Console.ResetColor();
            }
            Console.WriteLine("==================================================");

            // ==========================================
            // PHASE 1 DIAGNOSTICS: PROCESS HOSTING
            // ==========================================
            Console.WriteLine("\n[Phase 1] Resolving OpenCode CLI Binary...");
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

            Console.WriteLine("\n[Phase 1] Starting OpenCode Background Server...");
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

                    Console.WriteLine("\n[Phase 1] Performing Health Check...");
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

