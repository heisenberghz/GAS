using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace GAS.Core
{
    public static class OpenCodeConfigGenerator
    {
        public class ConfigInputs
        {
            public string ProviderName { get; set; } = "anthropic";
            public string DefaultAgent { get; set; } = "agent";
            public string WorkspaceDirectory { get; set; } = string.Empty;
            public bool SkillsEnabled { get; set; } = true;
            public bool CompactionEnabled { get; set; } = true;
            public bool MemoryEnabled { get; set; } = true;
            public List<string> EnabledSkills { get; set; } = new();
            public Dictionary<string, object>? ToolPermissions { get; set; }
        }

        /// <summary>
        /// Generates the opencode.json configuration file consumed by the OpenCode binary.
        /// Returns the path to the generated file.
        /// </summary>
        public static string Generate(ConfigInputs inputs)
        {
            var baseDir = string.IsNullOrEmpty(inputs.WorkspaceDirectory)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".gas")
                : inputs.WorkspaceDirectory;

            var configDir = Path.Combine(baseDir, "config");
            Directory.CreateDirectory(configDir);

            var configPath = Path.Combine(configDir, "opencode.json");

            // Skill permissions: deny all by default, allow enabled skills
            var skillPermissions = new Dictionary<string, string> { ["*"] = "deny" };
            foreach (var skill in inputs.EnabledSkills)
            {
                skillPermissions[skill] = "allow";
            }

            var permissions = inputs.ToolPermissions ?? new Dictionary<string, object>();
            permissions["skill"] = skillPermissions;

            // Default Agent definition
            var agentDict = new Dictionary<string, object>
            {
                ["agent"] = new Dictionary<string, object>
                {
                    ["description"] = "GAS Default Agent",
                    ["mode"] = "primary",
                    ["permission"] = permissions
                },
                ["plan"] = new Dictionary<string, object>
                {
                    ["description"] = "GAS Planning Agent",
                    ["mode"] = "subagent",
                    ["permission"] = new Dictionary<string, object> { ["edit"] = "deny" }
                }
            };

            // Instructions array pointing to workspace persona files
            var instructions = new List<string>();
            var personaFiles = new[] { "SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "MEMORY.md" };
            foreach (var file in personaFiles)
            {
                var filePath = Path.Combine(baseDir, file);
                if (File.Exists(filePath))
                {
                    instructions.Add(filePath);
                }
            }

            var config = new Dictionary<string, object>
            {
                ["$schema"] = "https://opencode.ai/config.json",
                ["default_agent"] = inputs.DefaultAgent,
                ["enabled_providers"] = new[] { inputs.ProviderName },
                ["permission"] = permissions,
                ["agent"] = agentDict
            };

            if (inputs.CompactionEnabled)
            {
                config["compaction"] = new Dictionary<string, object>
                {
                    ["auto"] = true,
                    ["prune"] = true
                };
            }

            if (instructions.Count > 0)
            {
                config["instructions"] = instructions;
            }

            var jsonOptions = new JsonSerializerOptions { WriteIndented = true };
            var json = JsonSerializer.Serialize(config, jsonOptions);
            File.WriteAllText(configPath, json);

            return configPath;
        }
    }
}
