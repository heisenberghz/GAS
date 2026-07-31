using System;
using System.Collections.Generic;

namespace GAS.Core
{
    public static class ToolPermissionPolicy
    {
        private static readonly HashSet<string> ProtectedPathPrefixes = new(StringComparer.OrdinalIgnoreCase)
        {
            @"C:\Windows",
            @"C:\Program Files",
            @"C:\Program Files (x86)",
            @"C:\System Volume Information"
        };

        /// <summary>
        /// Determines whether a tool operation should be automatically approved based on the current Trust Level.
        /// </summary>
        public static bool ShouldAutoApprove(TrustLevel level, string toolName, string? detail = null)
        {
            var normalizedTool = (toolName ?? "").ToLowerInvariant();

            // Always allow safe read-only tools across all trust levels
            if (normalizedTool.Contains("read") || normalizedTool.Contains("list") || 
                normalizedTool.Contains("glob") || normalizedTool.Contains("search") || 
                normalizedTool.Contains("grep"))
            {
                return true;
            }

            // Check system protected paths — NEVER auto-approve actions targeting system directories
            if (!string.IsNullOrEmpty(detail))
            {
                foreach (var protectedPath in ProtectedPathPrefixes)
                {
                    if (detail.StartsWith(protectedPath, StringComparison.OrdinalIgnoreCase))
                    {
                        return false;
                    }
                }
            }

            switch (level)
            {
                case TrustLevel.Careful:
                    // Careful: require approval for all file edits and shell commands
                    return false;

                case TrustLevel.Balanced:
                    // Balanced: auto-approve file edits, require approval for shell commands and file deletions
                    if (normalizedTool.Contains("delete") || normalizedTool.Contains("bash") || 
                        normalizedTool.Contains("terminal") || normalizedTool.Contains("shell") ||
                        normalizedTool.Contains("command"))
                    {
                        return false;
                    }
                    return true;

                case TrustLevel.Yolo:
                    // YOLO: auto-approve everything except protected system paths
                    return true;

                default:
                    return false;
            }
        }

        /// <summary>
        /// Generates the permission dictionary serialized into opencode.json for native engine enforcement.
        /// </summary>
        public static Dictionary<string, object> ToOpenCodePermissionRules(TrustLevel level)
        {
            return level switch
            {
                TrustLevel.Careful => new Dictionary<string, object>
                {
                    ["read"] = "allow",
                    ["glob"] = "allow",
                    ["grep"] = "allow",
                    ["list"] = "allow",
                    ["edit"] = "ask",
                    ["bash"] = "ask",
                    ["question"] = "allow"
                },
                TrustLevel.Balanced => new Dictionary<string, object>
                {
                    ["read"] = "allow",
                    ["glob"] = "allow",
                    ["grep"] = "allow",
                    ["list"] = "allow",
                    ["edit"] = "allow",
                    ["bash"] = "ask",
                    ["question"] = "allow"
                },
                TrustLevel.Yolo => new Dictionary<string, object>
                {
                    ["read"] = "allow",
                    ["glob"] = "allow",
                    ["grep"] = "allow",
                    ["list"] = "allow",
                    ["edit"] = "allow",
                    ["bash"] = "allow",
                    ["question"] = "allow"
                },
                _ => new Dictionary<string, object>()
            };
        }
    }
}
