using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;

namespace GAS.Core
{
    public static class EnvironmentBuilder
    {
        public class EnvironmentInputs
        {
            public string ProviderEnvKeyName { get; set; } = "ANTHROPIC_API_KEY";
            public string ApiKey { get; set; } = string.Empty;
            public string ConfigPath { get; set; } = string.Empty;
            public bool DebugMode { get; set; } = false;
        }

        /// <summary>
        /// Builds the environment variable dictionary for the OpenCode server subprocess.
        /// Configures CLI client mode, plan mode, PATH extensions, proxy cleanup, and API key environment settings.
        /// </summary>
        public static Dictionary<string, string> Build(EnvironmentInputs inputs)
        {
            var env = new Dictionary<string, string>();

            // Copy system environment variables
            foreach (DictionaryEntry de in Environment.GetEnvironmentVariables())
            {
                if (de.Key is string key && de.Value is string value)
                {
                    env[key] = value;
                }
            }

            // 1. Remove proxy variables to prevent SOCKS/Playwright/httpx failures
            var proxyKeys = new[]
            {
                "ALL_PROXY", "all_proxy",
                "HTTP_PROXY", "http_proxy",
                "HTTPS_PROXY", "https_proxy",
                "NO_PROXY", "no_proxy",
                "SOCKS_PROXY", "socks_proxy"
            };
            foreach (var proxyKey in proxyKeys)
            {
                env.Remove(proxyKey);
            }

            // 2. Extend PATH with common Node.js, Python, and .NET paths on Windows
            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);

            var pathAdditions = new[]
            {
                Path.Combine(programFiles, "nodejs"),
                Path.Combine(appData, "npm"),
                Path.Combine(userProfile, ".dotnet"),
                Path.Combine(userProfile, "AppData", "Local", "Programs", "Python", "Python311"),
                Path.Combine(userProfile, "AppData", "Local", "Programs", "Python", "Python312")
            };

            var existingPath = env.TryGetValue("PATH", out var currentPath) ? currentPath : string.Empty;
            var newPathParts = new List<string>();
            foreach (var addition in pathAdditions)
            {
                if (Directory.Exists(addition) && !existingPath.Contains(addition))
                {
                    newPathParts.Add(addition);
                }
            }
            if (!string.IsNullOrEmpty(existingPath))
            {
                newPathParts.Add(existingPath);
            }
            env["PATH"] = string.Join(";", newPathParts);

            // 3. Flags matching Motive execution
            env["TERM"] = "dumb";
            env["NO_COLOR"] = "1";
            env["FORCE_COLOR"] = "0";
            env["CI"] = "1";
            env["OPENCODE_CLIENT"] = "cli";
            env["OPENCODE_EXPERIMENTAL_PLAN_MODE"] = "1";

            // 4. Provider API key
            if (!string.IsNullOrWhiteSpace(inputs.ApiKey) && !string.IsNullOrWhiteSpace(inputs.ProviderEnvKeyName))
            {
                env[inputs.ProviderEnvKeyName] = inputs.ApiKey;
            }

            // 5. Generated OpenCode Config path
            if (!string.IsNullOrWhiteSpace(inputs.ConfigPath))
            {
                env["OPENCODE_CONFIG"] = inputs.ConfigPath;
            }

            if (inputs.DebugMode)
            {
                env["DEBUG"] = "1";
            }

            return env;
        }
    }
}
