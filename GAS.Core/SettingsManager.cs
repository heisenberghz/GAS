using System;
using System.IO;
using System.Text.Json;

namespace GAS.Core
{
    public class AppSettings
    {
        public bool StartOnBoot { get; set; } = false;
        public string CustomBinaryPath { get; set; } = string.Empty;
        public bool CtrlModifier { get; set; } = true;
        public bool ShiftModifier { get; set; } = true;
        public bool AltModifier { get; set; } = false;
        public string HotkeyKey { get; set; } = "Space";
        public string LastWorkspacePath { get; set; } = string.Empty;
        public string TrustMode { get; set; } = "Careful"; // Careful, Balanced, YOLO
        public string Theme { get; set; } = "Dark"; // Dark, Light, System
    }

    public static class SettingsManager
    {
        private static readonly string SettingsFilePath = Path.Combine(BinaryManager.AppSupportDirectory, "settings.json");
        private static readonly object Lock = new object();

        /// <summary>
        /// Loads the application settings from the JSON file.
        /// </summary>
        public static AppSettings Load()
        {
            lock (Lock)
            {
                if (!File.Exists(SettingsFilePath))
                {
                    return new AppSettings();
                }

                try
                {
                    string json = File.ReadAllText(SettingsFilePath);
                    return JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
                }
                catch
                {
                    return new AppSettings();
                }
            }
        }

        /// <summary>
        /// Saves the application settings to the JSON file.
        /// </summary>
        public static void Save(AppSettings settings)
        {
            lock (Lock)
            {
                try
                {
                    var dir = Path.GetDirectoryName(SettingsFilePath);
                    if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                    {
                        Directory.CreateDirectory(dir);
                    }

                    string json = JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true });
                    File.WriteAllText(SettingsFilePath, json);
                }
                catch (Exception ex)
                {
                    throw new InvalidOperationException("Failed to save application settings.", ex);
                }
            }
        }
    }
}

