using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace GAS.Core.Skills
{
    public class SkillDiscoveryResult
    {
        public List<string> DiscoveredSkillNames { get; set; } = new();
        public Dictionary<string, object> McpServers { get; set; } = new();
        public List<string> DiscoveredSkillPaths { get; set; } = new();
    }

    /// <summary>
    /// Discovers custom skills and MCP server configurations across workspace
    /// (.agents/skills, .opencode/skills) and global user directories (.gemini/config/skills, .opencode/skills).
    /// </summary>
    public static class SkillDiscoveryEngine
    {
        public static SkillDiscoveryResult Discover(string? workspaceDirectory)
        {
            var result = new SkillDiscoveryResult();
            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

            // 1. Candidate Skill Search Locations (Workspace local + Global user roots)
            var candidateDirectories = new List<string>();

            if (!string.IsNullOrWhiteSpace(workspaceDirectory) && Directory.Exists(workspaceDirectory))
            {
                candidateDirectories.Add(Path.Combine(workspaceDirectory, ".agents", "skills"));
                candidateDirectories.Add(Path.Combine(workspaceDirectory, ".opencode", "skills"));
                candidateDirectories.Add(Path.Combine(workspaceDirectory, ".gemini", "skills"));
                candidateDirectories.Add(Path.Combine(workspaceDirectory, ".claude", "skills"));
                candidateDirectories.Add(Path.Combine(workspaceDirectory, ".cursor", "skills"));
            }

            candidateDirectories.Add(Path.Combine(userProfile, ".gemini", "config", "skills"));
            candidateDirectories.Add(Path.Combine(userProfile, ".opencode", "skills"));
            candidateDirectories.Add(Path.Combine(userProfile, ".config", "opencode", "skills"));

            // 2. Scan directories for skill folders containing SKILL.md or skill.json
            foreach (var dir in candidateDirectories)
            {
                if (!Directory.Exists(dir)) continue;

                try
                {
                    var skillFolders = Directory.GetDirectories(dir);
                    foreach (var folder in skillFolders)
                    {
                        var skillName = Path.GetFileName(folder);
                        var mdPath = Path.Combine(folder, "SKILL.md");
                        var jsonPath = Path.Combine(folder, "skill.json");

                        if (File.Exists(mdPath) || File.Exists(jsonPath))
                        {
                            if (!result.DiscoveredSkillNames.Contains(skillName))
                            {
                                result.DiscoveredSkillNames.Add(skillName);
                                result.DiscoveredSkillPaths.Add(folder);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[SkillDiscoveryEngine] Error scanning directory {dir}: {ex.Message}");
                }
            }

            // 3. Scan for local MCP Server Configurations (mcp.json or .mcp.json)
            if (!string.IsNullOrWhiteSpace(workspaceDirectory) && Directory.Exists(workspaceDirectory))
            {
                var mcpJsonPaths = new[]
                {
                    Path.Combine(workspaceDirectory, "mcp.json"),
                    Path.Combine(workspaceDirectory, ".mcp.json"),
                    Path.Combine(workspaceDirectory, ".opencode", "mcp.json")
                };

                foreach (var mcpPath in mcpJsonPaths)
                {
                    if (File.Exists(mcpPath))
                    {
                        try
                        {
                            var content = File.ReadAllText(mcpPath);
                            using var doc = JsonDocument.Parse(content);
                            if (doc.RootElement.ValueKind == JsonValueKind.Object)
                            {
                                foreach (var prop in doc.RootElement.EnumerateObject())
                                {
                                    result.McpServers[prop.Name] = JsonSerializer.Deserialize<object>(prop.Value.GetRawText())!;
                                }
                            }
                        }
                        catch (Exception ex)
                        {
                            System.Diagnostics.Debug.WriteLine($"[SkillDiscoveryEngine] Error reading MCP config {mcpPath}: {ex.Message}");
                        }
                    }
                }
            }

            return result;
        }
    }
}
